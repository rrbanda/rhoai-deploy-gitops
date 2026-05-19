#!/bin/bash
# Stage B Validation: Governance and Multi-Tenancy
# Validates per-subscription auth, rate limiting, tiered access, and usage tracking
set -euo pipefail

MAAS_GATEWAY="${MAAS_GATEWAY:-$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.addresses[0].value}')}"
MODEL_NAME="${MODEL_NAME:-gemma2-9b-fp8}"
TOKEN="${API_TOKEN:-$(oc whoami -t)}"

echo "=== Stage B: Governance and Multi-Tenancy Validation ==="
echo ""

echo "--- B1: Per-Use-Case Authentication ---"
echo "Checking subscriptions..."
oc get maassubscription -n models-as-a-service -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,PRIORITY:.spec.priority
echo ""

echo "Testing invalid key returns 401..."
INVALID_RESPONSE=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer invalid-key-12345" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"${MODEL_NAME}\", \"messages\": [{\"role\": \"user\", \"content\": \"test\"}], \"max_tokens\": 5}" \
  "https://${MAAS_GATEWAY}/v1/chat/completions")
if [ "${INVALID_RESPONSE}" = "401" ] || [ "${INVALID_RESPONSE}" = "403" ]; then
  echo "PASS: Invalid key rejected with HTTP ${INVALID_RESPONSE}"
else
  echo "FAIL: Expected 401/403, got HTTP ${INVALID_RESPONSE}"
fi
echo ""

echo "--- B2: Token-Based Rate Limiting ---"
echo "Checking TokenRateLimitPolicy..."
oc get tokenratelimitpolicy -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.conditions[0].reason
echo ""

echo "--- B3: Tiered Access ---"
echo "Subscription tiers:"
oc get maassubscription -n models-as-a-service -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority,TOKEN_LIMIT:.spec.modelRefs[0].tokenRateLimits[0].limit,WINDOW:.spec.modelRefs[0].tokenRateLimits[0].window
echo ""

echo "--- B2/B3: Burst Load Test ---"
echo "Sending rapid requests to trigger rate limiting..."
PASS_COUNT=0
RATE_LIMITED=0
for i in $(seq 1 20); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"${MODEL_NAME}\", \"messages\": [{\"role\": \"user\", \"content\": \"Count from 1 to 100 in words.\"}], \"max_tokens\": 500}" \
    "https://${MAAS_GATEWAY}/v1/chat/completions")
  if [ "${HTTP_CODE}" = "429" ]; then
    RATE_LIMITED=$((RATE_LIMITED + 1))
  elif [ "${HTTP_CODE}" = "200" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
  echo "  Request ${i}: HTTP ${HTTP_CODE}"
done
echo ""
echo "Results: ${PASS_COUNT} passed, ${RATE_LIMITED} rate-limited (429)"
if [ "${RATE_LIMITED}" -gt 0 ]; then
  echo "PASS: Rate limiting is active"
else
  echo "INFO: No rate limiting triggered (may need higher burst or lower limits for demo)"
fi
echo ""

echo "--- B4: Usage Tracking ---"
echo "Checking Limitador metrics..."
LIMITADOR_POD=$(oc get pods -n kuadrant-system -l app=limitador -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "${LIMITADOR_POD}" ]; then
  echo "Limitador metrics:"
  oc exec -n kuadrant-system "${LIMITADOR_POD}" -- curl -s http://localhost:8080/metrics 2>/dev/null | grep "authorized"
  echo ""
  echo "PASS: Usage metrics available"
else
  echo "SKIP: Limitador pod not found"
fi
echo ""

echo "=== Stage B Validation Complete ==="
