#!/usr/bin/env python3
"""Exercise chart-rendered telemetry trust with exact native arm64 image pairs."""

import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import signal
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from http.client import HTTPException
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "helm-charts/sawmills-collector"
FIXTURES = CHART / "tests/fixtures/telemetry-trust"
CA_PATH = "/etc/otel/certs/ca-cert.pem"
CASES = {
    "forward": ("new", "old"),
    "reverse": ("old", "new"),
    "old": ("old", "old"),
    "new": ("new", "new"),
}


class ExecutionBudget:
    """One batch owner reserves cleanup time inside each hard case deadline."""

    def __init__(self):
        self.batch_end = time.monotonic() + 1200
        self.case_end = float("inf")
        self.cleaning = False

    def timeout(self, requested):
        reserve = 0 if self.cleaning else 30
        remaining = min(self.batch_end, self.case_end) - time.monotonic() - reserve
        if remaining <= 0:
            raise TimeoutError("telemetry trust execution budget exhausted")
        return min(requested, remaining)


BUDGET = ExecutionBudget()


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def metric_epoch(timestamp):
    """Accept Go's variable subsecond precision on Python 3.10 and newer."""
    normalized = timestamp.replace(" +0000 UTC", "+00:00").replace("Z", "+00:00")
    normalized = re.sub(
        r"\.(\d+)(?=[+-]\d{2}:\d{2}$)",
        lambda match: "." + match[1][:6].ljust(6, "0"),
        normalized,
    )
    return datetime.datetime.fromisoformat(normalized).timestamp()


def command(args, *, timeout=45):
    result = subprocess.run(
        args,
        capture_output=True,
        check=False,
        text=True,
        timeout=BUDGET.timeout(timeout),
    )
    if result.returncode:
        raise RuntimeError(
            f"command failed ({result.returncode}): {args[0:3]}: {result.stderr[-2000:]}"
        )
    return result.stdout


def inspect(name):
    return json.loads(command(["docker", "inspect", name]))[0]


def http(url, body=None):
    timeout = BUDGET.timeout(2)
    request = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read(4 * 1024 * 1024).decode()
    except (urllib.error.URLError, OSError, HTTPException):
        return None, ""


def metric_points(message):
    """Decode the native receiver debug export, after PromRW acceptance."""
    resource, attrs, destination, name, stamp = {}, {}, None, None, None
    points = []
    for line in message.splitlines():
        if line.startswith("ResourceMetrics #"):
            resource, destination = {}, None
        elif line == "Resource attributes:":
            destination = resource
        elif line.startswith(("ScopeMetrics #", "Metric #")):
            destination = None
        elif line.startswith("     -> Name: "):
            name = line.removeprefix("     -> Name: ")
        elif line.startswith("NumberDataPoints #"):
            attrs, stamp, destination = {}, None, None
        elif line == "Data point attributes:":
            destination = attrs
        elif line.startswith("     -> ") and destination is not None:
            match = re.fullmatch(r"     -> (.*?): (Str|Int|Double|Bool)\((.*)\)", line)
            if match:
                destination[match[1]] = match[3]
        elif line.startswith("StartTimestamp:"):
            destination = None
        elif line.startswith("Timestamp: "):
            stamp = line.removeprefix("Timestamp: ")
        elif line.startswith("Value: ") and name and stamp:
            points.append(
                {
                    "name": name,
                    "resource": dict(resource),
                    "attributes": dict(attrs),
                    "timestamp": stamp,
                    "value": float(line.removeprefix("Value: ")),
                }
            )
    return points


def receiver_points(logs):
    points = []
    for line in logs.splitlines():
        record = json.loads(line)
        if record.get("otelcol.component.id") == "debug/metrics":
            points.extend(metric_points(record.get("msg", "")))
    return [p for p in points if p["resource"].get("service.name") == "otel-collector"]


def prepare(directory):
    values = json.loads((FIXTURES / "values.json").read_text())
    bundle = (
        "\n".join(
            (FIXTURES / (role + "-ca.pem")).read_text().strip()
            for role in ("old", "new")
        )
        + "\n"
    )
    values["loadBalancer"]["telemetryTrust"] = {"caBundlePem": bundle}
    path = directory / "values.json"
    path.write_text(json.dumps(values))
    rendered = command(
        [
            os.environ.get("HELM_BIN", "helm"),
            "template",
            "flt691-offline",
            str(CHART),
            "-n",
            "flt691-offline",
            "-f",
            str(path),
        ]
    )
    # Secret documents never reach an artifact. All inputs are synthetic/public.
    docs = [
        d
        for d in yaml.safe_load_all(rendered)
        if isinstance(d, dict) and d.get("kind") != "Secret"
    ]
    deployment = next(
        d
        for d in docs
        if d.get("kind") == "Deployment" and d["metadata"]["name"].endswith("-lb")
    )
    maps = {
        d["metadata"]["name"]: d.get("data") or {}
        for d in docs
        if d.get("kind") == "ConfigMap"
    }
    volumes = {v["name"]: v for v in deployment["spec"]["template"]["spec"]["volumes"]}
    containers = {
        c["name"]: c for c in deployment["spec"]["template"]["spec"]["containers"]
    }
    mounts = {}
    for name in ("main-collector", "telemetry-collector"):
        mounts[name] = []
        for index, mount in enumerate(containers[name]["volumeMounts"]):
            if mount["mountPath"] == "/tmp":
                continue
            if mount["mountPath"] not in ("/etc/otel/config.yaml", CA_PATH):
                raise AssertionError("unexpected fixture mount: " + mount["mountPath"])
            volume = volumes[mount["name"]]
            content = maps[volume["configMap"]["name"]][mount["subPath"]]
            target = directory / f"{name}-{index}.txt"
            target.write_text(content)
            target.chmod(0o644)
            mounts[name] += ["-v", f"{target}:{mount['mountPath']}:ro"]
            if mount["mountPath"] == CA_PATH:
                assert mount.get("readOnly") is True
    (directory / "rendered-trust.json").write_text(
        json.dumps(
            {
                "mounts": {
                    name: [
                        m
                        for m in containers[name]["volumeMounts"]
                        if m["mountPath"] == CA_PATH
                    ]
                    for name in mounts
                },
                "bundle_sha256": hashlib.sha256(bundle.encode()).hexdigest(),
            },
            indent=2,
        )
    )
    return mounts


def run_case(case, directory, images):
    BUDGET.case_end = time.monotonic() + 300
    directory.mkdir()
    mounts = prepare(directory)
    run = "telemetry-trust-" + uuid.uuid4().hex[:12]
    network = run + "-net"
    owned = []
    result = {"case": case, "started_at": utc(), "samples": [], "pass": False}
    environment = {
        "MY_POD_IP": "0.0.0.0",
        "PROMETHEUS_PORT": "8888",
        "MY_POD_NAME": run + "-main",
        "COLLECTOR_GATEWAY_ENDPOINT": "flt691-worker:4317",
        "COLLECTOR_GATEWAY_API_KEY": "SYNTHETIC",
        "PROMETHEUS_REMOTE_WRITE_ENDPOINT": "http://flt691-worker:9221/api/v1/write",
        "PROMETHEUS_REMOTE_WRITE_API_KEY": "SYNTHETIC",
    }

    def launch(name, image, role, network_args, extra):
        owned.append(name)
        args = [
            "docker",
            "run",
            "-d",
            "--name",
            name,
            "--label",
            "telemetry.trust.test=" + run,
            "--memory",
            "512m" if role == "sidecar" else "768m",
            "--memory-swap",
            "512m" if role == "sidecar" else "768m",
            "--cpus",
            "0.5" if role == "sidecar" else "1",
            "--pids-limit",
            "128",
            *network_args,
            *extra,
        ]
        for key, value in environment.items():
            args += ["-e", key + "=" + value]
        command([*args, image, "--config=/etc/otel/config.yaml"])

    try:
        worker = directory / "worker.yaml"
        worker.write_text(
            yaml.safe_dump(
                {
                    "receivers": {
                        "otlp": {"protocols": {"grpc": {"endpoint": "0.0.0.0:4317"}}},
                        "prometheusremotewrite": {
                            "endpoint": "0.0.0.0:9221",
                            "metrics_url_path": "/api/v1/write",
                        },
                    },
                    "exporters": {
                        "debug/logs": {"verbosity": "basic"},
                        "debug/metrics": {
                            "verbosity": "detailed",
                            "sampling_initial": 10000,
                            "sampling_thereafter": 10000,
                        },
                    },
                    "service": {
                        "telemetry": {"logs": {"encoding": "json"}},
                        "pipelines": {
                            "logs": {
                                "receivers": ["otlp"],
                                "exporters": ["debug/logs"],
                            },
                            "metrics": {
                                "receivers": ["prometheusremotewrite"],
                                "exporters": ["debug/metrics"],
                            },
                        },
                    },
                }
            )
        )
        worker.chmod(0o644)
        command(
            [
                "docker",
                "network",
                "create",
                "--internal",
                "--label",
                "telemetry.trust.test=" + run,
                network,
            ]
        )
        launch(
            run + "-worker",
            images["old"]["image"],
            "worker",
            ["--network", network, "--network-alias", "flt691-worker"],
            ["-v", str(worker) + ":/etc/otel/config.yaml:ro"],
        )
        main, side = CASES[case]
        launch(
            run + "-main",
            images[main]["image"],
            "main",
            ["--network", network],
            mounts["main-collector"],
        )
        launch(
            run + "-sidecar",
            images[side]["image"],
            "sidecar",
            ["--network", "container:" + run + "-main"],
            mounts["telemetry-collector"],
        )
        before = {name: inspect(name) for name in owned}
        ip = before[run + "-main"]["NetworkSettings"]["Networks"][network]["IPAddress"]
        start, complete = time.monotonic(), []
        previous_counters = {}
        last_complete_epoch = 0
        while time.monotonic() - start < 120:
            payload = {
                "resourceLogs": [
                    {
                        "scopeLogs": [
                            {
                                "logRecords": [
                                    {
                                        "timeUnixNano": str(time.time_ns()),
                                        "body": {"stringValue": "synthetic-trust-test"},
                                    }
                                    for _ in range(20)
                                ]
                            }
                        ]
                    }
                ]
            }
            status, _ = http(
                "http://" + ip + ":4318/v1/logs", json.dumps(payload).encode()
            )
            metrics_status, text = http("http://" + ip + ":8888/metrics")
            lines = [
                s
                for s in text.splitlines()
                if not s.startswith("#") and 'job="otel-collector"' in s
            ]
            names = {s.split("{", 1)[0].split(" ", 1)[0] for s in lines}
            # Docker sends the collector's JSON logs on stderr.
            log_read = subprocess.run(
                ["docker", "logs", "--tail", "20000", run + "-worker"],
                capture_output=True,
                check=False,
                text=True,
                timeout=BUDGET.timeout(10),
            )
            assert log_read.returncode == 0
            points = receiver_points(log_read.stdout + log_read.stderr)
            required = [
                "target_info",
                "otelcol_receiver_accepted_log_records_total",
                "otelcol_exporter_sent_log_records_total",
                "otelcol_loadbalancer_central_queue_compressed_bytes",
                "otelcol_loadbalancer_central_queue_items",
                "otelcol_loadbalancer_central_queue_inflight_uncompressed_bytes",
            ]
            current = time.time()
            fresh = [
                p for p in points if 0 <= current - metric_epoch(p["timestamp"]) < 30
            ]
            covered = metrics_status == 200 and all(k in names for k in required)
            received = {
                name: [p for p in fresh if p["name"] == name] for name in required
            }
            remote_covered = all(received.values())
            epochs = [
                max(metric_epoch(p["timestamp"]) for p in group)
                for group in received.values()
                if group
            ]
            coverage_epoch = min(epochs) if remote_covered else 0
            accepted = all(
                any(p["value"] > 0 for p in received[name])
                for name in [
                    "otelcol_receiver_accepted_log_records_total",
                    "otelcol_exporter_sent_log_records_total",
                ]
            )
            counters = {}
            for name in [
                "otelcol_receiver_accepted_log_records_total",
                "otelcol_exporter_sent_log_records_total",
            ]:
                for point in received[name]:
                    key = json.dumps(
                        [name, point["resource"], point["attributes"]], sort_keys=True
                    )
                    if key not in counters or point["timestamp"] > counters[key][0]:
                        counters[key] = (point["timestamp"], point["value"])
            assert all(
                key not in previous_counters or value[1] >= previous_counters[key][1]
                for key, value in counters.items()
            ), "unresolved main counter reset"
            previous_counters.update(counters)
            sample = {
                "at": utc(),
                "http": status,
                "main_series": len(lines),
                "main_families": sorted(names),
                "fresh_received_main_points": len(fresh),
                "coverage": covered,
                "positive_received_traffic": accepted,
                "fresh_received_families": sorted(
                    name for name, group in received.items() if group
                ),
                "received_coverage_epoch": coverage_epoch,
            }
            result["samples"].append(sample)
            if covered and remote_covered and accepted and status == 200:
                if coverage_epoch > last_complete_epoch:
                    complete.append(time.monotonic())
                    last_complete_epoch = coverage_epoch
                if len(complete) >= 2 and complete[-1] - complete[0] >= 5:
                    result["pass"] = True
                    break
            else:
                complete = []
            time.sleep(BUDGET.timeout(10))
        for name in owned:
            after = inspect(name)
            assert after["State"]["Running"] and after["RestartCount"] == 0
            assert (
                before[name]["Id"] == after["Id"]
                and before[name]["State"]["StartedAt"] == after["State"]["StartedAt"]
            )
        main_log = subprocess.run(
            ["docker", "logs", "--tail", "20000", run + "-main"],
            capture_output=True,
            check=False,
            text=True,
            timeout=BUDGET.timeout(10),
        )
        assert main_log.returncode == 0
        text = main_log.stdout + main_log.stderr
        result["x509_error_lines"] = sum("x509:" in line for line in text.splitlines())
        result["loopback_x509_lines"] = sum(
            "x509:" in line and "127.0.0.1:14317" in line for line in text.splitlines()
        )
        result["stable_processes"] = True
        if result["x509_error_lines"]:
            result["pass"] = False
        result["cause"] = (
            None if result["pass"] else "main_metrics_missing_or_tls_error"
        )
    except Exception as error:
        result["pass"] = False
        result["error"] = str(error)
        raise
    finally:
        BUDGET.cleaning = True
        cleanup = []
        cleanup_errors = []
        for name in reversed(owned):
            try:
                found = subprocess.run(
                    ["docker", "inspect", name],
                    capture_output=True,
                    check=False,
                    text=True,
                    timeout=BUDGET.timeout(10),
                )
                if found.returncode:
                    assert "No such" in found.stderr, found.stderr
                    continue
                assert (
                    json.loads(found.stdout)[0]["Config"]["Labels"][
                        "telemetry.trust.test"
                    ]
                    == run
                )
                command(["docker", "rm", "-f", name])
                cleanup.append(name)
            except (
                AssertionError,
                KeyError,
                OSError,
                RuntimeError,
                ValueError,
                subprocess.SubprocessError,
            ) as error:
                cleanup_errors.append({"name": name, "error": str(error)})
        remaining = "UNKNOWN"
        try:
            remaining = len(
                command(
                    [
                        "docker",
                        "ps",
                        "-aq",
                        "--filter",
                        "label=telemetry.trust.test=" + run,
                    ]
                ).split()
            )
            networks = command(
                [
                    "docker",
                    "network",
                    "ls",
                    "-q",
                    "--filter",
                    "label=telemetry.trust.test=" + run,
                ]
            ).strip()
            if networks:
                command(["docker", "network", "rm", network])
        except (
            AssertionError,
            KeyError,
            OSError,
            RuntimeError,
            ValueError,
            subprocess.SubprocessError,
        ) as error:
            cleanup_errors.append({"stage": "ownership_readback", "error": str(error)})
        if cleanup_errors or remaining != 0:
            result["pass"] = False
        result.update(
            {
                "cleanup_at": utc(),
                "removed": cleanup,
                "owned_remaining": remaining,
                "cleanup_errors": cleanup_errors,
            }
        )
        (directory / "result.json").write_text(json.dumps(result, indent=2))
        BUDGET.case_end = float("inf")
        BUDGET.cleaning = False
        assert (
            not cleanup_errors and remaining == 0
        ), "owned resource cleanup incomplete"
    print(json.dumps(result), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", default="forward,reverse,old,new")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    assert platform.machine() in (
        "aarch64",
        "arm64",
    ), "native arm64 required, no emulation/skip"
    assert command(["docker", "info", "--format", "{{.Architecture}}"]).strip() in (
        "aarch64",
        "arm64",
    )
    args.output = args.output.resolve()
    args.output.mkdir()
    images = json.loads((FIXTURES / "images.json").read_text())
    for role, binding in images.items():
        pem = FIXTURES / (role + "-ca.pem")
        der = subprocess.run(
            ["openssl", "x509", "-in", str(pem), "-outform", "DER"],
            capture_output=True,
            check=False,
            timeout=BUDGET.timeout(10),
        )
        assert (
            der.returncode == 0
            and hashlib.sha256(der.stdout).hexdigest() == binding["ca_sha256"]
        )
        valid = subprocess.run(
            ["openssl", "x509", "-in", str(pem), "-checkend", "0", "-noout"],
            capture_output=True,
            check=False,
            timeout=BUDGET.timeout(10),
        )
        assert valid.returncode == 0, (
            f"fixture certificate expired for {role}; refresh the pinned image pair "
            "and its public CA fixtures"
        )
        if subprocess.run(
            ["docker", "image", "inspect", binding["image"]],
            capture_output=True,
            check=False,
            timeout=BUDGET.timeout(45),
        ).returncode:
            command(
                ["docker", "pull", "--platform", "linux/arm64", binding["image"]],
                timeout=300,
            )
        image = json.loads(command(["docker", "image", "inspect", binding["image"]]))[0]
        assert image["Architecture"] == "arm64" and binding["image"] in image.get(
            "RepoDigests", []
        )
    results = [
        run_case(case, args.output / case, images) for case in args.cases.split(",")
    ]
    (args.output / "result.json").write_text(json.dumps(results, indent=2))
    return 0 if all(r["pass"] for r in results) else 1


if __name__ == "__main__":

    def terminate(_signum, _frame):
        raise TimeoutError("test owner terminated")

    signal.signal(signal.SIGTERM, terminate)
    raise SystemExit(main())
