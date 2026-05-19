#!/bin/bash
# Stage C Validation: Observability and Enterprise Integration
# Validates metrics collection, dashboards, and monitoring infrastructure
set -euo pipefail

echo "=== Stage C: Observability Validation ==="
echo ""

echo "--- C3.1: User Workload Monitoring ---"
echo "Checking Prometheus user workload pods..."
oc get pods -n openshift-user-workload-monitoring -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase
echo ""

echo "--- C3.2: ServiceMonitors ---"
echo "Active ServiceMonitors for AI Bridge:"
oc get servicemonitor -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name 2>/dev/null | grep -E "kuadrant|limitador|authorino|kserve|llm"
echo ""

echo "--- C3.3: Limitador Rate Limit Metrics ---"
LIMITADOR_POD=$(oc get pods -n kuadrant-system -l app=limitador -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "${LIMITADOR_POD}" ]; then
  echo "Per-route authorized calls:"
  oc exec -n kuadrant-system "${LIMITADOR_POD}" -- curl -s http://localhost:8080/metrics 2>/dev/null | grep "authorized_"
  echo ""
fi

echo "--- C3.4: vLLM Inference Metrics ---"
echo "KServe LLM ServiceMonitors:"
oc get servicemonitor -A 2>/dev/null | grep "kserve-llm"
echo ""

echo "--- C3.5: Dashboard ---"
DASHBOARD=$(oc get configmap ai-gateway-dashboard -n openshift-config-managed -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [ -n "${DASHBOARD}" ]; then
  echo "PASS: AI Gateway dashboard ConfigMap deployed"
  echo "Panels:"
  oc get configmap ai-gateway-dashboard -n openshift-config-managed -o jsonpath='{.data}' | python3 -c "
import json, sys
data = json.load(sys.stdin)
for key, val in data.items():
    dashboard = json.loads(val)
    print(f'  Dashboard: {dashboard.get(\"title\",\"?\")}')
    for panel in dashboard.get('panels',[]):
        print(f'    - {panel.get(\"title\",\"?\")} ({panel.get(\"type\",\"?\")})')
" 2>/dev/null
else
  echo "FAIL: Dashboard ConfigMap not found"
fi
echo ""

echo "--- C1: OIDC/SSO Status ---"
OAUTH_CONFIG=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}' 2>/dev/null || echo "")
if [ -n "${OAUTH_CONFIG}" ]; then
  echo "Identity providers configured: ${OAUTH_CONFIG}"
else
  echo "INFO: No external IdP configured (requires enterprise IdP details)"
fi
echo ""

echo "--- C2: External Secrets Operator ---"
ESO_PODS=$(oc get pods -A -l app.kubernetes.io/name=external-secrets -o name 2>/dev/null | wc -l)
if [ "${ESO_PODS}" -gt 0 ]; then
  echo "PASS: ESO deployed (${ESO_PODS} pods)"
else
  echo "INFO: ESO not deployed (requires enterprise Vault instance)"
fi
echo ""

echo "=== Stage C Validation Complete ==="
