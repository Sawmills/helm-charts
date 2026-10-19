"""Preserve the immutable public 2.0.18 Helm render contract."""

import copy
import hashlib
import sys
import unittest
from pathlib import Path

sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[2] / "sawmills-remote-operator-compat/tests"),
)
from test_compatibility import remove_version_labels, render  # noqa: E402

sys.path.insert(
    0,
    str(
        Path(__file__).resolve().parents[2]
        / "sawmills-remote-operator-2023-compat/tests"
    ),
)
from test_compatibility_2023 import DRAIN  # noqa: E402

CHART = Path(__file__).resolve().parents[1]
BASELINE = Path(__file__).with_name("operator-2.0.18.tgz")
BASELINE_SHA256 = "2d6214e2d98e8b07f06564e166061d9f110f7f3e29f4a00aa6044f49c6413007"


class Compatibility2018Test(unittest.TestCase):
    def test_upgrade_preserves_default_2018_objects_and_one_gib_memory(self):
        self.assertEqual(
            hashlib.sha256(BASELINE.read_bytes()).hexdigest(), BASELINE_SHA256
        )
        deployment = next(
            obj for (kind, _), obj in render(CHART, {}).items() if kind == "Deployment"
        )
        self.assertEqual(
            deployment["spec"]["template"]["spec"]["containers"][0]["resources"][
                "limits"
            ]["memory"],
            "1Gi",
        )
        self.assert_contract({"apiKeyExistingSecret": "synthetic-existing-secret"})

    def test_values_ignored_by_2018_do_not_enable_new_autoscaler_or_analytics(self):
        self.assert_contract(
            {
                "apiKeyExistingSecret": "synthetic-existing",
                "analyticsExistingSecret": "synthetic-ignored-analytics",
                "analyticsExistingSecretKey": "synthetic-routing",
                "autoscaler": {
                    "enabled": True,
                    "globalMinReplicas": 9,
                    "globalMaxReplicas": 2,
                },
                "managedChartsValues": {"sawmills-collector": {"replicaCount": 3}},
            }
        )

    def test_preserves_proxy_scheduling_resources_and_customer_references(self):
        self.assert_contract(
            {
                "apiKeyExistingSecret": "synthetic-custom-secret",
                "apiKeyExistingSecretKey": "custom-key",
                "collectorName": "proof-{{ .Release.Namespace }}",
                "operatorAddress": "https://manager.example.invalid",
                "remoteWriteUrl": "https://ingress.example.invalid",
                "selfManaged": True,
                "proxy": {
                    "http": "http://proxy.example.invalid:3128",
                    "https": "http://secure.example.invalid:3128",
                    "noProxy": ["localhost", ".svc"],
                },
                "managedChartsValues": {"sawmills-collector": {"replicaCount": 7}},
                "managedChartsOverrides": {
                    "collector": {
                        "chart": "oci://registry.example.invalid/collector",
                        "version": "9.8.7",
                    }
                },
                "rbac": {
                    "serviceAccountName": "custom-sa",
                    "roleName": "custom-role",
                    "roleBindingName": "custom-binding",
                },
                "nodeSelector": {"pool": "proof"},
                "tolerations": [{"key": "proof", "operator": "Exists"}],
                "affinity": {
                    "podAntiAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": []
                    }
                },
                "resources": {
                    "requests": {"cpu": "170m", "memory": "300Mi"},
                    "limits": {"cpu": "700m", "memory": "1100Mi"},
                },
                "cacheVolume": {"sizeLimit": "700Mi"},
                "image": {
                    "repository": "registry.example.invalid/operator",
                    "tag": "synthetic-tag",
                    "pullPolicy": "Always",
                },
            }
        )

    def test_preserves_names_optional_rbac_generated_secret_and_legacy_alias(self):
        cases = [
            {
                "apiKeyExistingSecret": "synthetic-existing",
                "nameOverride": "legacy-name",
                "fullnameOverride": "legacy-deployment",
                "rbac": {
                    "createServiceAccount": False,
                    "createRole": False,
                    "createRoleBinding": False,
                },
            },
            {
                "apiKey": "synthetic-fixture-only",
                "managedCharts": {
                    "collector": {"endpoint": "{{ .Values.operatorAddress }}"}
                },
                "proxy": {"noProxy": "localhost,.svc"},
            },
            {
                "apiKeyExistingSecret": "synthetic-existing",
                "proxy": {"https": "http://proxy.example.invalid:3128"},
            },
        ]
        for values in cases:
            with self.subTest(values=values):
                self.assert_contract(values)

    def assert_contract(self, values):
        image = {"tag": "0.343.0", **values.get("image", {})}
        before = render(BASELINE, {**values, "image": image})
        after = render(CHART, values)
        self.assertEqual(set(after), set(before), "resource identity changed")
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
                    pod["spec"].pop("terminationGracePeriodSeconds", None), 14400
                )
                container = pod["spec"]["containers"][0]
                repository = image.get(
                    "repository", "public.ecr.aws/s7a5m1b4/sawmills-remote-operator"
                )
                self.assertEqual(container["image"], repository + ":" + image["tag"])
                self.assertEqual(container.pop("lifecycle", None), DRAIN)
                uid = [env for env in container["env"] if env["name"] == "POD_UID"]
                self.assertEqual(
                    uid,
                    [
                        {
                            "name": "POD_UID",
                            "valueFrom": {"fieldRef": {"fieldPath": "metadata.uid"}},
                        }
                    ],
                )
                container["env"] = [
                    env for env in container["env"] if env["name"] != "POD_UID"
                ]
                for item in (old, new):
                    remove_version_labels(item["spec"]["template"]["metadata"])
            self.assertEqual(new, old, f"unapproved render change: {identity}")


if __name__ == "__main__":
    unittest.main()
