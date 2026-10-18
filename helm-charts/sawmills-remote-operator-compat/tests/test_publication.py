"""Exercise the publishing action's real package with registry calls isolated."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

CHART = Path(__file__).resolve().parents[1]
ROOT = CHART.parents[1]


class PublicationTest(unittest.TestCase):
    def package(self, app_version):
        action = yaml.safe_load(
            (ROOT / ".github/actions/push-helm/action.yml").read_text()
        )
        prepare = next(
            step
            for step in action["runs"]["steps"]
            if step.get("name") == "Prepare Helm chart"
        )
        real_helm = shutil.which("helm")
        self.assertIsNotNone(real_helm)
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            binaries = temporary / "bin"
            binaries.mkdir()
            helm = binaries / "helm"
            helm.write_text(
                "#!/bin/bash\nset -euo pipefail\n"
                'case "$1" in\n'
                '  package) exec "$REAL_HELM" "$@" ;;\n'
                '  registry) [[ "$#" == 6 && "$2" == login && "$3" == --username && "$4" == AWS && "$5" == --password-stdin && "$6" == registry.example.invalid ]] && cat >/dev/null ;;\n'
                '  push) [[ "$#" == 3 && -f "$2" && "$3" == oci://registry.example.invalid ]] ;;\n'
                "  *) exit 91 ;;\n"
                "esac\n"
            )
            helm.chmod(0o700)
            aws = binaries / "aws"
            aws.write_text(
                "#!/bin/bash\nset -euo pipefail\n"
                '[[ "$1 $2" == "ecr-public get-login-password" ]]\n'
                'printf "synthetic-token\\n"\n'
            )
            aws.chmod(0o700)
            inputs = {
                "chart-name": "sawmills-remote-operator-compat-chart",
                "chart-path": str(CHART),
                "chart-repo": "registry.example.invalid",
                "tag": "remote-operator-compat-v1.0.0",
                "app-version": app_version,
                "aws_region": "us-east-1",
            }
            environment = {
                **os.environ,
                "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
                "REAL_HELM": real_helm,
            }
            for name, value in prepare["env"].items():
                for key, argument in inputs.items():
                    value = value.replace("${{ inputs." + key + " }}", argument)
                value = value.replace("${{ runner.temp }}", str(temporary))
                self.assertNotIn("${{", value, "unbound action environment")
                environment[name] = value
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", prepare["run"]],
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            package = (
                temporary / "charts/sawmills-remote-operator-compat-chart-1.0.0.tgz"
            )
            metadata = yaml.safe_load(
                subprocess.check_output(
                    [real_helm, "show", "chart", str(package)], text=True
                )
            )
            self.assertEqual(metadata["version"], "1.0.0")
            objects = yaml.safe_load_all(
                subprocess.check_output(
                    [
                        real_helm,
                        "template",
                        "publication-proof",
                        str(package),
                        "--set",
                        "apiKeyExistingSecret=synthetic-secret",
                    ],
                    text=True,
                )
            )
            deployment = next(
                item for item in objects if item and item["kind"] == "Deployment"
            )
            self.assertEqual(
                deployment["spec"]["template"]["spec"]["containers"][0]["image"],
                "public.ecr.aws/s7a5m1b4/sawmills-remote-operator:0.342.0",
            )
            return metadata

    def test_package_keeps_operator_version_separate_from_chart_version(self):
        workflow = yaml.safe_load(
            (
                ROOT / ".github/workflows/deploy-sawmills-remote-operator-compat.yml"
            ).read_text()
        )
        publish = next(
            step["with"]
            for step in workflow["jobs"]["build-and-deploy"]["steps"]
            if step.get("name") == "Publish compatibility chart"
        )
        expected = "0.342.0"

        metadata = self.package(publish["app-version"])

        self.assertEqual(metadata["appVersion"], expected)

    def test_existing_callers_keep_tag_derived_application_version(self):
        self.assertEqual(self.package("")["appVersion"], "1.0.0")


if __name__ == "__main__":
    unittest.main()
