"""Compare public renders with the immutable installed-chart baseline."""

import copy
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

CHART = Path(__file__).resolve().parents[1]
BASELINE = CHART / "tests/operator-2.0.5.tgz"
BASELINE_SHA256 = "99c3de228f30dec88a479918a67058d34ceea5822b7a38e96c61ee032488fbb3"


def render(chart, values):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml") as source:
        yaml.safe_dump(values, source)
        source.flush()
        result = subprocess.run(
            [
                "helm",
                "template",
                "sawmills-remote-operator",
                str(chart),
                "--namespace",
                "sawmills",
                "--values",
                source.name,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    if result.returncode:
        raise AssertionError(f"helm template failed: {result.stderr}")
    objects = [item for item in yaml.safe_load_all(result.stdout) if item]
    return {(item["kind"], item["metadata"]["name"]): item for item in objects}


def remove_version_labels(metadata):
    labels = metadata.get("labels", {})
    labels.pop("helm.sh/chart", None)
    labels.pop("app.kubernetes.io/version", None)


class CompatibilityTest(unittest.TestCase):
    def test_upgrade_preserves_installed_contract(self):
        self.assertEqual(
            hashlib.sha256(BASELINE.read_bytes()).hexdigest(), BASELINE_SHA256
        )
        cases = [
            {"apiKeyExistingSecret": "existing-secret"},
            {
                "apiKeyExistingSecret": "custom-secret",
                "apiKeyExistingSecretKey": "custom-key",
                "collectorName": "eu-{{ .Release.Namespace }}",
                "operatorAddress": "https://manager.example.invalid",
                "managedCharts": {
                    "collector": {
                        "endpoint": "{{ .Values.operatorAddress }}",
                        "replicas": 7,
                    }
                },
                "rbac": {
                    "serviceAccountName": "custom-sa",
                    "roleName": "custom-role",
                    "roleBindingName": "custom-binding",
                },
                "affinity": {
                    "podAntiAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": []
                    }
                },
                "nodeSelector": {"pool": "proof"},
                "tolerations": [{"key": "proof", "operator": "Exists"}],
                "resources": {
                    "requests": {"cpu": "170m", "memory": "300Mi"},
                    "limits": {"cpu": "700m", "memory": "1100Mi"},
                },
                "cacheVolume": {"sizeLimit": "700Mi"},
            },
            {
                "apiKeyExistingSecret": "existing-secret",
                "nameOverride": "legacy-name",
                "fullnameOverride": "legacy-deployment",
                "rbac": {
                    "createServiceAccount": False,
                    "createRole": False,
                    "createRoleBinding": False,
                },
            },
            {"apiKey": "synthetic-fixture-only"},
            {
                "apiKeyExistingSecret": "existing-secret",
                "image": {"tag": "synthetic-tag"},
            },
        ]
        for values in cases:
            with self.subTest(case=cases.index(values)):
                tag = values.get("image", {}).get("tag", "0.340.0")
                before = render(BASELINE, {**values, "image": {"tag": tag}})
                after = render(CHART, values)
                self.assertEqual(
                    set(after), set(before), "object identity must remain stable"
                )
                for identity, old in before.items():
                    old, new = copy.deepcopy(old), copy.deepcopy(after[identity])
                    remove_version_labels(old["metadata"])
                    remove_version_labels(new["metadata"])
                    if identity[0] == "Deployment":
                        pod = new["spec"]["template"]
                        self.assertEqual(
                            pod["metadata"]["labels"].pop(
                                "sawmills.ai/health-gated-recovery", None
                            ),
                            "v1",
                        )
                        self.assertEqual(
                            pod["spec"].pop("terminationGracePeriodSeconds", None),
                            14400,
                        )
                        container = pod["spec"]["containers"][0]
                        self.assertEqual(
                            container["image"],
                            "public.ecr.aws/s7a5m1b4/sawmills-remote-operator:" + tag,
                        )
                        self.assertEqual(
                            container.pop("lifecycle", None),
                            {
                                "preStop": {
                                    "exec": {
                                        "command": [
                                            "/bin/sh",
                                            "-c",
                                            "curl --noproxy '*' --fail --silent --show-error -X POST http://127.0.0.1:8086/drain",
                                        ]
                                    }
                                }
                            },
                        )
                        uid = [
                            env for env in container["env"] if env["name"] == "POD_UID"
                        ]
                        self.assertEqual(
                            uid,
                            [
                                {
                                    "name": "POD_UID",
                                    "valueFrom": {
                                        "fieldRef": {"fieldPath": "metadata.uid"}
                                    },
                                }
                            ],
                        )
                        container["env"] = [
                            env for env in container["env"] if env["name"] != "POD_UID"
                        ]
                        container["image"] = old["spec"]["template"]["spec"][
                            "containers"
                        ][0]["image"]
                        for item in (old, new):
                            metadata = item["spec"]["template"]["metadata"]
                            remove_version_labels(metadata)
                    self.assertEqual(new, old, f"unapproved render change: {identity}")


if __name__ == "__main__":
    unittest.main()
