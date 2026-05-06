#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-sawmills-o11y}"
RELEASE="${RELEASE:-sawmills-collector}"
KUBIE_ENV="${KUBIE_ENV:-staging}"
QUERY="${QUERY:-sum(otelcol_loadbalancer_central_queue_compressed_bytes)}"
TARGET="${TARGET:-10485760}"
SCALER_SVC="${SCALER_SVC:-${RELEASE}-keda-otel-scaler}"
MONITORING_PORT="${MONITORING_PORT:-19465}"
SCALEDOBJECT="${SCALEDOBJECT:-${RELEASE}-keda-hpa}"
HPA="${HPA:-keda-hpa-${SCALEDOBJECT}}"
MODE="${MODE:-happy}"

run() {
	kubie exec "${KUBIE_ENV}" "${NAMESPACE}" -- kubectl "$@"
}

ignore_run() {
	set +e
	run "$@"
	set -e
}

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

pass() {
	echo "PASS: $*"
}

json_query="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${QUERY}")"

case "${MODE}" in
happy | bad-path | bad-query | scaler-late | zero-query) ;;
*) fail "unknown MODE ${MODE}" ;;
esac

if [[ ${MODE} == "bad-path" ]]; then
	echo "Running bad-path failure mode"
	original_url="$(run get scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.url}')"
	restore_url() {
		ignore_run patch scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" --type=json -p="[{\"op\":\"replace\",\"path\":\"/spec/triggers/0/metadata/url\",\"value\":\"${original_url}\"}]" >/dev/null
	}
	trap restore_url EXIT
	bad_url="${original_url%/query*}/missing"
	run patch scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" --type=json -p="[{\"op\":\"replace\",\"path\":\"/spec/triggers/0/metadata/url\",\"value\":\"${bad_url}\"}]"
	sleep 45
	hpa_metric_type="$(run get hpa "${HPA}" -n "${NAMESPACE}" -o jsonpath='{.spec.metrics[0].type}')"
	[[ ${hpa_metric_type} == "External" ]] || fail "bad-path changed HPA metric type to ${hpa_metric_type}"
	restore_url
	trap - EXIT
	pass "bad-path failure kept HPA External and restored original URL"
	exit 0
fi

if [[ ${MODE} == "bad-query" ]]; then
	echo "Running bad-query failure mode"
	original_url="$(run get scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.url}')"
	restore_url() {
		ignore_run patch scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" --type=json -p="[{\"op\":\"replace\",\"path\":\"/spec/triggers/0/metadata/url\",\"value\":\"${original_url}\"}]" >/dev/null
	}
	trap restore_url EXIT
	bad_url="${original_url%%query=*}query=sum%28"
	run patch scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" --type=json -p="[{\"op\":\"replace\",\"path\":\"/spec/triggers/0/metadata/url\",\"value\":\"${bad_url}\"}]"
	sleep 45
	hpa_metric_type="$(run get hpa "${HPA}" -n "${NAMESPACE}" -o jsonpath='{.spec.metrics[0].type}')"
	[[ ${hpa_metric_type} == "External" ]] || fail "bad-query changed HPA metric type to ${hpa_metric_type}"
	restore_url
	trap - EXIT
	pass "bad-query failure kept HPA External and restored original URL"
	exit 0
fi

if [[ ${MODE} == "zero-query" ]]; then
	echo "Running zero-query failure mode"
	original_url="$(run get scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metadata.url}')"
	restore_url() {
		ignore_run patch scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" --type=json -p="[{\"op\":\"replace\",\"path\":\"/spec/triggers/0/metadata/url\",\"value\":\"${original_url}\"}]" >/dev/null
	}
	trap restore_url EXIT
	zero_query="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' 'sum(sawmills_central_queue_keda_zero_probe_metric)')"
	zero_url="${original_url%%query=*}query=${zero_query}"
	run patch scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" --type=json -p="[{\"op\":\"replace\",\"path\":\"/spec/triggers/0/metadata/url\",\"value\":\"${zero_url}\"}]"
	sleep 45
	hpa_metric_type="$(run get hpa "${HPA}" -n "${NAMESPACE}" -o jsonpath='{.spec.metrics[0].type}')"
	[[ ${hpa_metric_type} == "External" ]] || fail "zero-query changed HPA metric type to ${hpa_metric_type}"

	curl_pod="sm-keda-zero-query-check-$(date +%s)"
	cleanup_zero_pod() {
		ignore_run delete pod "${curl_pod}" -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1
	}
	cleanup_zero_pod
	trap 'cleanup_zero_pod; restore_url' EXIT
	run run "${curl_pod}" -n "${NAMESPACE}" --restart=Never --image=curlimages/curl:8.15.0 --command -- \
		curl -fsS "${zero_url}" >/dev/null
	set +e
	run wait pod/"${curl_pod}" -n "${NAMESPACE}" --for=jsonpath='{.status.phase}'=Succeeded --timeout=60s
	wait_status=$?
	set -e
	if ((wait_status != 0)); then
		ignore_run logs "${curl_pod}" -n "${NAMESPACE}"
		fail "zero-query GET pod did not complete"
	fi
	zero_result="$(run logs "${curl_pod}" -n "${NAMESPACE}")"
	result_value="$(
		QUERY_RESULT="${zero_result}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["QUERY_RESULT"])
value = payload.get("result")
if value != 0:
    raise SystemExit(f"result is {value}, not 0")
print(value)
PY
	)"
	cleanup_zero_pod
	restore_url
	trap - EXIT
	pass "zero-query returned ${result_value} and kept HPA External"
	exit 0
fi

if [[ ${MODE} == "scaler-late" ]]; then
	echo "Running scaler-late failure mode"
	restore_scaler() {
		ignore_run scale deployment "${SCALER_SVC}" -n "${NAMESPACE}" --replicas=1 >/dev/null
	}
	trap restore_scaler EXIT
	run scale deployment "${SCALER_SVC}" -n "${NAMESPACE}" --replicas=0
	sleep 10
	scaler_late_timestamp="$(date +%s)"
	run annotate scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" "sawmills.ai/scaler-late-test=${scaler_late_timestamp}" --overwrite
	sleep 30
	hpa_metric_type="$(run get hpa "${HPA}" -n "${NAMESPACE}" -o jsonpath='{.spec.metrics[0].type}')"
	[[ ${hpa_metric_type} == "External" ]] || fail "scaler-late changed HPA metric type to ${hpa_metric_type}"
	restore_scaler
	trap - EXIT
	run rollout status "deployment/${SCALER_SVC}" -n "${NAMESPACE}" --timeout=120s
	pass "scaler-late failure kept HPA External and restored scaler"
	exit 0
fi

echo "Checking rollout status"
run rollout status "deployment/${RELEASE}" -n "${NAMESPACE}" --timeout=120s
run rollout status "deployment/${RELEASE}-lb" -n "${NAMESPACE}" --timeout=120s
run rollout status "deployment/${SCALER_SVC}" -n "${NAMESPACE}" --timeout=120s

echo "Checking ScaledObject trigger"
trigger_type="$(run get scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].type}')"
[[ ${trigger_type} == "metrics-api" ]] || fail "expected metrics-api trigger, got ${trigger_type}"
pass "ScaledObject trigger is metrics-api"

metric_type="$(run get scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" -o jsonpath='{.spec.triggers[0].metricType}')"
[[ ${metric_type} == "AverageValue" ]] || fail "expected AverageValue, got ${metric_type}"
pass "ScaledObject metricType is AverageValue"

echo "Checking HPA"
hpa_metric_type="$(run get hpa "${HPA}" -n "${NAMESPACE}" -o jsonpath='{.spec.metrics[0].type}')"
[[ ${hpa_metric_type} == "External" ]] || fail "expected External HPA metric, got ${hpa_metric_type}"
pass "HPA metric type is External"

hpa_target="$(run get hpa "${HPA}" -n "${NAMESPACE}" -o jsonpath='{.spec.metrics[0].external.target.averageValue}')"
[[ ${hpa_target} == "${TARGET}" ]] || fail "expected target ${TARGET}, got ${hpa_target}"
pass "HPA target is ${TARGET}"

echo "Checking direct GET query"
curl_pod="sm-keda-metrics-api-check-$(date +%s)"
cleanup_curl_pod() {
	ignore_run delete pod "${curl_pod}" -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1
}
cleanup_curl_pod
trap cleanup_curl_pod EXIT
run run "${curl_pod}" -n "${NAMESPACE}" --restart=Never --image=curlimages/curl:8.15.0 --command -- \
	curl -fsS "http://${SCALER_SVC}:${MONITORING_PORT}/query?query=${json_query}" >/dev/null
set +e
run wait pod/"${curl_pod}" -n "${NAMESPACE}" --for=jsonpath='{.status.phase}'=Succeeded --timeout=60s
wait_status=$?
set -e
if ((wait_status != 0)); then
	ignore_run logs "${curl_pod}" -n "${NAMESPACE}"
	fail "direct GET query pod did not complete"
fi
query_result="$(run logs "${curl_pod}" -n "${NAMESPACE}")"
cleanup_curl_pod
trap - EXIT

result_value="$(
	QUERY_RESULT="${query_result}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["QUERY_RESULT"])
value = payload.get("result")
if not isinstance(value, (int, float)):
    raise SystemExit("result is not numeric")
print(value)
PY
)"
pass "direct GET query returned numeric result ${result_value}"

replicas="$(run get deployment "${RELEASE}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')"
[[ -n ${replicas} && ${replicas} != "0" ]] || fail "collector ready replicas is ${replicas:-empty}"

hpa_current="$(run get hpa "${HPA}" -n "${NAMESPACE}" -o jsonpath='{.status.currentMetrics[0].external.current.averageValue}')"
pass "HPA current AverageValue is ${hpa_current}; query result ${result_value}; ready replicas ${replicas}"

echo "Checking KEDA conditions"
conditions="$(run get scaledobject "${SCALEDOBJECT}" -n "${NAMESPACE}" -o jsonpath='{range .status.conditions[*]}{.type}={.status}:{.reason}{"\n"}{end}')"
printf '%s\n' "${conditions}"
printf '%s\n' "${conditions}" | grep -q 'Ready=True:ScaledObjectReady' || fail "ScaledObject is not ready"
pass "ScaledObject Ready=True"

echo "Checking recent KEDA operator errors"
set +e
operator_related="$(kubie exec "${KUBIE_ENV}" "${NAMESPACE}" -- kubectl logs -n keda-system deploy/keda-operator --since=10m --tail=1000 | grep -Ei "${SCALEDOBJECT}|metrics-api")"
operator_status=$?
set -e
if ((operator_status != 0)); then
	operator_related=""
fi
printf '%s\n' "${operator_related}"
if printf '%s\n' "${operator_related}" | grep -Eiq 'error|failed|unable|invalid'; then
	fail "KEDA operator logs contain recent errors"
fi
pass "No recent KEDA operator errors for ${SCALEDOBJECT}"

echo "Checking pod restarts"
set +e
run get pods -n "${NAMESPACE}" | grep -E "${RELEASE}|${SCALER_SVC}"
set -e
pass "staging central queue metrics-api validation completed"
