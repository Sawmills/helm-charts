"""Preserve the exact public 0.163.0 objects across a recovery upgrade."""

import copy
import hashlib
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[2] / "sawmills-remote-operator-compat/tests"),
)
import test_compatibility as legacy  # noqa: E402
from child_receipts import run  # noqa: E402

sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[2] / "sawmills-remote-operator-2023-compat/tests"),
)
from test_compatibility_2023 import DRAIN  # noqa: E402

CHART = Path(__file__).resolve().parents[1]
BASELINE = Path(__file__).with_name("operator-0.163.0.tgz")
BASELINE_SHA256 = "783a2c46bac6a871f45645268c66fd7480c48cdce2daf5b12c16078ceaa645bd"


render = legacy.render


class Compatibility0163Test(unittest.TestCase):
    def test_default_upgrade_preserves_0163_native_and_rbac_contract(self):
        self.assertEqual(
            hashlib.sha256(BASELINE.read_bytes()).hexdigest(), BASELINE_SHA256
        )
        self.assert_contract({})

    def test_existing_secret_grpc_and_resource_settings_keep_their_meaning(self):
        self.assert_contract(
            {
                "apiKeyExistingSecret": "synthetic-existing-secret",
                "collectorName": "literal-{{ .Release.Namespace }}",
                "operatorAddress": "manager.example.invalid:443",
                "grpcTrace": "all",
                "replicaCount": 1,
                "image": {"pullPolicy": "IfNotPresent"},
                "cacheVolume": {"sizeLimit": "700Mi"},
                "resources": {
                    "requests": {"cpu": "170m", "memory": "300Mi"},
                    "limits": {"cpu": "700m", "memory": "1100Mi"},
                },
            }
        )

    def test_generated_secret_and_custom_names_keep_their_legacy_shapes(self):
        cases = [
            {
                "apiKey": "synthetic-fixture-only",
                "nameOverride": "custom-name",
                "replicaCount": 0,
                "grpcTrace": "",
            },
            {
                "apiKeyExistingSecret": "synthetic-existing",
                "fullnameOverride": "custom-deployment",
                "nameOverride": "custom-selector",
            },
            {"nameOverride": "synthetic-long-name-" * 5},
        ]
        for values in cases:
            with self.subTest(values=values):
                self.assert_contract(values)

    def test_modern_values_remain_ignored_by_the_0163_contract(self):
        self.assert_contract(
            {
                "apiKeyExistingSecret": "synthetic-existing",
                "apiKeyExistingSecretKey": "ignored-key",
                "image": {"tag": "ignored-tag", "repository": "ignored.invalid"},
                "securityContext": {"runAsUser": 2000, "runAsGroup": 2000},
                "rbac": {
                    "createServiceAccount": False,
                    "createRole": False,
                    "createRoleBinding": False,
                    "serviceAccountName": "ignored-sa",
                    "roleName": "ignored-role",
                    "roleBindingName": "ignored-binding",
                },
                "nodeSelector": {"pool": "ignored"},
                "tolerations": [{"key": "ignored", "operator": "Exists"}],
                "affinity": {"nodeAffinity": {}},
                "logLevel": "debug",
                "remoteWriteUrl": "https://ignored.example.invalid",
                "selfManaged": True,
                "proxy": {"http": "http://ignored.example.invalid:3128"},
                "managedCharts": {"collector": {"replicaCount": 7}},
                "managedChartsValues": {"collector": {"replicaCount": 9}},
                "managedChartsOverrides": {"collector": {"version": "9.8.7"}},
                "autoscaler": {"enabled": True},
                "analyticsExistingSecret": "synthetic-ignored",
            }
        )

    def test_package_excludes_test_inputs_and_preserves_the_contract(self):
        with tempfile.TemporaryDirectory() as destination:
            result = run(
                ["helm", "package", str(CHART), "--destination", destination],
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, str(result.receipt_path))
            archives = list(Path(destination).glob("*.tgz"))
            self.assertEqual(len(archives), 1)
            with tarfile.open(archives[0]) as package:
                self.assertTrue(
                    all("tests" not in Path(item.name).parts for item in package)
                )
            self.assert_contract({}, chart=archives[0])

    def test_chart_passes_native_helm_lint(self):
        result = run(
            ["helm", "lint", str(CHART)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, str(result.receipt_path))

    def assert_contract(self, values, chart=CHART):
        before = render(BASELINE, values)
        after = render(chart, values)
        self.assertEqual(set(after), set(before), "resource identity changed")
        for identity, old in before.items():
            old, new = copy.deepcopy(old), copy.deepcopy(after[identity])
            legacy.remove_version_labels(old["metadata"])
            legacy.remove_version_labels(new["metadata"])
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
                self.assertEqual(
                    container["image"],
                    "public.ecr.aws/s7a5m1b4/sawmills-remote-operator:0.343.0",
                )
                container["image"] = old["spec"]["template"]["spec"]["containers"][0][
                    "image"
                ]
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
                    metadata = item["spec"]["template"]["metadata"]
                    legacy.remove_version_labels(metadata)
                    self.assertRegex(
                        metadata["annotations"].pop("rollme"), r"^[A-Za-z0-9]{5}$"
                    )
            self.assertEqual(new, old, f"unapproved render change: {identity}")


if __name__ == "__main__":
    unittest.main()
