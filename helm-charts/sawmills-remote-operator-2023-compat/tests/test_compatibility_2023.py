"""Preserve the public 2.0.23 contract through an operator-only upgrade."""

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

CHART = Path(__file__).resolve().parents[1]
BASELINE = Path(__file__).with_name("operator-2.0.23.tgz")
BASELINE_SHA256 = "e054cf7bd788b161931f644693ea6d78da8694b6ef85c82d3f56785f410356ab"
DRAIN = {
    "preStop": {
        "exec": {
            "command": [
                "/bin/sh",
                "-c",
                "curl --noproxy '*' --fail --silent --show-error -X POST http://127.0.0.1:8086/drain",
            ]
        }
    }
}


class Compatibility2023Test(unittest.TestCase):
    def test_upgrade_preserves_2023_objects_except_declared_recovery_changes(self):
        self.assertEqual(
            hashlib.sha256(BASELINE.read_bytes()).hexdigest(), BASELINE_SHA256
        )
        values = {"apiKeyExistingSecret": "synthetic-existing-secret"}
        self.assert_contract(values)

    def test_preserves_proxy_analytics_autoscaler_and_customer_references(self):
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
                "analyticsExistingSecret": "synthetic-analytics",
                "analyticsExistingSecretKey": "routing",
                "managedChartsValues": {
                    "sawmills-collector": {
                        "replicaCount": 7,
                        "metricsClickhouseRouting": {"enabled": True},
                    }
                },
                "managedChartsOverrides": {
                    "collector": {
                        "chart": "oci://registry.example.invalid/collector",
                        "version": "9.8.7",
                    }
                },
                "autoscaler": {
                    "enabled": True,
                    "dryRun": False,
                    "metricsEndpoint": "http://metrics.example.invalid",
                    "otlpMetricsEndpoint": "http://otlp.example.invalid",
                    "targetHPAName": "custom-hpa",
                    "leaseName": "custom-lease",
                    "labelSelectors": {"proof": "yes"},
                    "memoryLimitBytes": 123456789,
                    "globalMinReplicas": 2,
                    "globalMaxReplicas": 9,
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

    def test_preserves_names_optional_rbac_and_generated_secret(self):
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

    def test_preserves_invalid_autoscaler_rejection(self):
        for chart in (BASELINE, CHART):
            with self.subTest(chart=chart):
                with self.assertRaisesRegex(
                    AssertionError, "globalMinReplicas cannot be greater"
                ):
                    render(
                        chart,
                        {
                            "autoscaler": {
                                "enabled": True,
                                "globalMinReplicas": 9,
                                "globalMaxReplicas": 2,
                            }
                        },
                    )

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
