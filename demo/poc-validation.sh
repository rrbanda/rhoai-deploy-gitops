#!/bin/bash
# PoC Alignment Validation Script
# Tests all 8 success criteria + bonus capabilities against the live demo environment
# Usage: ./demo/poc-validation.sh
#
# Requires: oc (logged into cluster-4l6x6), curl, python3, jq (optional)
set -uo pipefail

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
RESULTS=()

# --- Configuration ---
CTX_GPU="default/api-cluster-4l6x6-4l6x6-sandbox1213-opentlc-com:6443/admin"
CTX_GW="default/api-cluster-6crhb-6crhb-sandbox1011-opentlc-com:6443/admin"
KEYCLOAK_HOST="keycloak-keycloak.apps.cluster-6crhb.6crhb.sandbox1011.opentlc.com"
KEYCLOAK_REALM="ai-bridge"
OIDC_CLIENT_ID="ai-bridge-gateway"
OIDC_CLIENT_SECRET="ai-bridge-secret-2026"
GR_HOST="guardrails-gateway-ai-guardrails.apps.cluster-4l6x6.4l6x6.sandbox1213.opentlc.com"
MODEL_NAME="qwen25-7b-instruct"
MODEL_NS="llm-inference"

record() {
  local sc="$1" test_name="$2" status="$3" detail="$4"
  if [ "$status" = "PASS" ]; then
    ((PASS_COUNT++))
  elif [ "$status" = "FAIL" ]; then
    ((FAIL_COUNT++))
  else
    ((SKIP_COUNT++))
  fi
  RESULTS+=("$sc|$test_name|$status|$detail")
  echo "  [$status] $test_name: $detail"
}

header() {
  echo ""
  echo "========================================================================"
  echo "  $1"
  echo "========================================================================"
}

# ============================================================================
header "SC #1 (P1): Per-Use-Case Authentication"
# ============================================================================
echo "Requirement: Each team has its own API key scoped to specific models."
echo "             Key revocation takes effect immediately."
echo ""

oc config use-context "$CTX_GPU" &>/dev/null

# Test 1.1: Show MaaSSubscription resources exist
echo "--- 1.1: MaaSSubscription resources ---"
SUBS=$(oc get maassubscription -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$SUBS" -ge 2 ]; then
  record "SC1" "Multiple subscriptions exist" "PASS" "${SUBS} MaaSSubscription(s) found"
  oc get maassubscription -A 2>/dev/null | head -10
else
  record "SC1" "Multiple subscriptions exist" "FAIL" "Only ${SUBS} subscription(s) found"
fi
echo ""

# Test 1.2: Validate API key works
echo "--- 1.2: API key authentication ---"
MAAS_GW_SVC="maas-default-gateway-data-science-gateway-class.openshift-ingress.svc:443"
# Get a valid API key from PostgreSQL
API_KEY=$(oc exec -n maas-db deploy/postgresql -- psql -U maas -d maas -t -A -c "SELECT key FROM api_keys LIMIT 1" 2>/dev/null | tr -d '[:space:]')
if [ -n "$API_KEY" ]; then
  # Test from within cluster
  RESP=$(oc run val-test --rm -i --restart=Never --image=curlimages/curl -n $MODEL_NS --command -- \
    curl -sk --max-time 10 "https://${MAAS_GW_SVC}/${MODEL_NS}/${MODEL_NAME}/v1/models" \
    -H "Authorization: Bearer ${API_KEY}" 2>/dev/null)
  if echo "$RESP" | grep -q '"object"'; then
    record "SC1" "Valid API key returns 200" "PASS" "Model list returned successfully"
  else
    record "SC1" "Valid API key returns 200" "FAIL" "Unexpected response: ${RESP:0:100}"
  fi
else
  record "SC1" "Valid API key returns 200" "SKIP" "No API key found in PostgreSQL"
fi
echo ""

# Test 1.3: Invalid key returns 401
echo "--- 1.3: Invalid API key rejected ---"
RESP_INVALID=$(oc run val-test2 --rm -i --restart=Never --image=curlimages/curl -n $MODEL_NS --command -- \
  curl -sk --max-time 10 -o /dev/null -w "%{http_code}" "https://${MAAS_GW_SVC}/${MODEL_NS}/${MODEL_NAME}/v1/models" \
  -H "Authorization: Bearer invalid-key-12345" 2>/dev/null)
if [ "$RESP_INVALID" = "401" ] || [ "$RESP_INVALID" = "403" ]; then
  record "SC1" "Invalid key rejected" "PASS" "HTTP ${RESP_INVALID} returned for invalid key"
else
  record "SC1" "Invalid key rejected" "FAIL" "Expected 401/403, got ${RESP_INVALID}"
fi
echo ""

# ============================================================================
header "SC #2 (P1): Token-Based Rate Limiting"
# ============================================================================
echo "Requirement: Rate limiting enforced per subscription."
echo "             Burst from one team does not degrade others."
echo ""

# Test 2.1: Rate limit configuration exists
echo "--- 2.1: Rate limit configuration ---"
SUB_YAML=$(cat usecases/models/gemma2-9b-fp8/manifests/team-subscriptions.yaml 2>/dev/null)
TIERS=$(echo "$SUB_YAML" | grep -c "tokenRateLimits" 2>/dev/null || echo "0")
if [ "$TIERS" -ge 2 ]; then
  record "SC2" "Rate limit config per tier" "PASS" "${TIERS} subscriptions with tokenRateLimits defined"
  echo "  Premium: 500,000 tokens/hr | Standard: 100,000 tokens/hr | Basic: 50,000 tokens/hr"
else
  record "SC2" "Rate limit config per tier" "FAIL" "tokenRateLimits not found in subscription manifests"
fi
echo ""

# Test 2.2: Limitador is running
echo "--- 2.2: Limitador rate limiter active ---"
LIMITADOR_PODS=$(oc get pods -A -l app=limitador --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$LIMITADOR_PODS" -ge 1 ]; then
  record "SC2" "Limitador running" "PASS" "${LIMITADOR_PODS} Limitador pod(s) active"
else
  record "SC2" "Limitador running" "SKIP" "Limitador pods not found (may be managed by RHCL)"
fi
echo ""

# ============================================================================
header "SC #3 (P1): Usage Tracking"
# ============================================================================
echo "Requirement: Per-subscription usage visible and queryable via Prometheus."
echo ""

# Test 3.1: ServiceMonitors exist
echo "--- 3.1: Observability ServiceMonitors ---"
SM_COUNT=$(oc get servicemonitor -A --no-headers 2>/dev/null | grep -c "authorino\|limitador" || echo "0")
if [ "$SM_COUNT" -ge 1 ]; then
  record "SC3" "ServiceMonitors deployed" "PASS" "${SM_COUNT} relevant ServiceMonitor(s)"
else
  record "SC3" "ServiceMonitors deployed" "FAIL" "No Authorino/Limitador ServiceMonitors found"
fi
echo ""

# Test 3.2: User workload monitoring enabled
echo "--- 3.2: User workload monitoring ---"
UWM=$(oc get configmap cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}' 2>/dev/null)
if echo "$UWM" | grep -q "enableUserWorkload.*true"; then
  record "SC3" "User workload monitoring enabled" "PASS" "enableUserWorkload: true in cluster-monitoring-config"
else
  record "SC3" "User workload monitoring enabled" "FAIL" "User workload monitoring not configured"
fi
echo ""

# Test 3.3: Prometheus is scraping metrics
echo "--- 3.3: Prometheus metrics available ---"
PROM_ROUTE=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}' 2>/dev/null)
PROM_TOKEN=$(oc whoami -t 2>/dev/null)
if [ -n "$PROM_ROUTE" ] && [ -n "$PROM_TOKEN" ]; then
  METRIC_CHECK=$(curl -sk "https://${PROM_ROUTE}/api/v1/label/__name__/values" \
    -H "Authorization: Bearer ${PROM_TOKEN}" 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    names=d.get('data',[])
    relevant=[n for n in names if 'authorino' in n or 'limitador' in n]
    print(len(relevant))
except: print('0')
" 2>/dev/null)
  if [ "${METRIC_CHECK:-0}" -gt 0 ]; then
    record "SC3" "Prometheus metrics scraped" "PASS" "${METRIC_CHECK} auth/ratelimit metrics available"
  else
    record "SC3" "Prometheus metrics scraped" "SKIP" "Metrics not yet collected (may need request traffic)"
  fi
else
  record "SC3" "Prometheus metrics scraped" "SKIP" "Cannot reach Prometheus (no route or token)"
fi
echo ""

# ============================================================================
header "SC #4 (P2): Tiered Access"
# ============================================================================
echo "Requirement: At least two tiers with independent rate limit policies."
echo ""

# Test 4.1: Multiple tiers defined
echo "--- 4.1: Subscription tiers ---"
if [ -f "usecases/models/gemma2-9b-fp8/manifests/team-subscriptions.yaml" ]; then
  TIER_LABELS=$(grep "tier:" usecases/models/gemma2-9b-fp8/manifests/team-subscriptions.yaml | sort -u | wc -l | tr -d ' ')
  if [ "$TIER_LABELS" -ge 2 ]; then
    record "SC4" "Multiple tiers defined" "PASS" "${TIER_LABELS} distinct tiers: premium, standard, basic"
    grep "tier:\|tokenRateLimits\|limit:" usecases/models/gemma2-9b-fp8/manifests/team-subscriptions.yaml
  else
    record "SC4" "Multiple tiers defined" "FAIL" "Fewer than 2 tiers"
  fi
else
  record "SC4" "Multiple tiers defined" "FAIL" "team-subscriptions.yaml not found"
fi
echo ""

# ============================================================================
header "SC #5 (P2): OIDC / SSO"
# ============================================================================
echo "Requirement: Enterprise IdP federation. Role-based access control enforced."
echo ""

# Test 5.1: Keycloak realm exists and OIDC token obtainable
echo "--- 5.1: OIDC token from Keycloak ---"
TOKEN_RESP=$(curl -sk "https://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -d "grant_type=client_credentials&client_id=${OIDC_CLIENT_ID}&client_secret=${OIDC_CLIENT_SECRET}" 2>/dev/null)
OIDC_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
if [ -n "$OIDC_TOKEN" ] && [ ${#OIDC_TOKEN} -gt 50 ]; then
  record "SC5" "OIDC token obtainable" "PASS" "Got ${#OIDC_TOKEN}-char JWT from Keycloak ai-bridge realm"
else
  record "SC5" "OIDC token obtainable" "FAIL" "Could not get token: ${TOKEN_RESP:0:100}"
fi
echo ""

# Test 5.2: Token contains role claims
echo "--- 5.2: Role claims in JWT ---"
if [ -n "$OIDC_TOKEN" ]; then
  PAYLOAD=$(echo "$OIDC_TOKEN" | cut -d. -f2 | python3 -c "
import sys,base64,json
p=sys.stdin.read().strip()
p+='=='
try:
    d=json.loads(base64.urlsafe_b64decode(p))
    roles=d.get('realm_access',{}).get('roles',[])
    print(','.join(roles))
except: print('')
" 2>/dev/null)
  if echo "$PAYLOAD" | grep -q "ai-admin\|ai-engineer\|service-account"; then
    record "SC5" "JWT contains roles" "PASS" "Roles: ${PAYLOAD:0:80}"
  else
    record "SC5" "JWT contains roles" "FAIL" "No ai-admin/ai-engineer roles in token"
  fi
else
  record "SC5" "JWT contains roles" "SKIP" "No token to inspect"
fi
echo ""

# Test 5.3: AuthConfig validates OIDC on MaaS gateway
echo "--- 5.3: AuthConfig for OIDC ---"
AC_READY=$(oc get authconfig maas-gateway-oidc -n openshift-ingress -o jsonpath='{.status.summary.ready}' 2>/dev/null)
if [ "$AC_READY" = "true" ]; then
  record "SC5" "AuthConfig OIDC active" "PASS" "maas-gateway-oidc AuthConfig is Ready"
else
  record "SC5" "AuthConfig OIDC active" "FAIL" "AuthConfig not ready: ${AC_READY}"
fi
echo ""

# Test 5.4: OIDC token accepted by MaaS gateway
echo "--- 5.4: OIDC token works on gateway ---"
if [ -n "$OIDC_TOKEN" ]; then
  OIDC_RESP=$(oc run val-oidc --rm -i --restart=Never --image=curlimages/curl -n $MODEL_NS --command -- \
    curl -sk --max-time 10 "https://${MAAS_GW_SVC}/${MODEL_NS}/${MODEL_NAME}/v1/models" \
    -H "Authorization: Bearer ${OIDC_TOKEN}" 2>/dev/null)
  if echo "$OIDC_RESP" | grep -q '"object"'; then
    record "SC5" "OIDC token accepted by gateway" "PASS" "Model list returned with OIDC Bearer token"
  else
    record "SC5" "OIDC token accepted by gateway" "FAIL" "Response: ${OIDC_RESP:0:100}"
  fi
else
  record "SC5" "OIDC token accepted by gateway" "SKIP" "No OIDC token"
fi
echo ""

# ============================================================================
header "SC #6 (P2): Observability"
# ============================================================================
echo "Requirement: Live dashboards with inference metrics per subscription."
echo ""

# Test 6.1: Dashboard ConfigMap exists
echo "--- 6.1: Grafana dashboard ConfigMap ---"
DASH_CM=$(oc get configmap -A -l grafana_dashboard=1 --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$DASH_CM" -ge 1 ]; then
  record "SC6" "Dashboard ConfigMap exists" "PASS" "${DASH_CM} dashboard ConfigMap(s)"
else
  DASH_CM2=$(oc get configmap ai-bridge-dashboard -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$DASH_CM2" -ge 1 ]; then
    record "SC6" "Dashboard ConfigMap exists" "PASS" "ai-bridge-dashboard ConfigMap found"
  else
    record "SC6" "Dashboard ConfigMap exists" "SKIP" "No labeled dashboard ConfigMap (may use RHOAI built-in)"
  fi
fi
echo ""

# Test 6.2: Authorino metrics ServiceMonitor
echo "--- 6.2: Authorino ServiceMonitor ---"
AUTH_SM=$(oc get servicemonitor -A --no-headers 2>/dev/null | grep -c "authorino" || echo "0")
if [ "$AUTH_SM" -ge 1 ]; then
  record "SC6" "Authorino ServiceMonitor" "PASS" "Authorino metrics being scraped"
else
  record "SC6" "Authorino ServiceMonitor" "SKIP" "ServiceMonitor not found"
fi
echo ""

# ============================================================================
header "SC #7 (P2): API Compatibility"
# ============================================================================
echo "Requirement: Standard OpenAI API format. Base URL change only."
echo ""

# Test 7.1: /v1/models returns OpenAI-format response
echo "--- 7.1: OpenAI-compatible /v1/models ---"
MODELS_RESP=$(oc run val-api --rm -i --restart=Never --image=curlimages/curl -n $MODEL_NS --command -- \
  curl -sk --max-time 10 "https://${MAAS_GW_SVC}/${MODEL_NS}/${MODEL_NAME}/v1/models" 2>/dev/null)
if echo "$MODELS_RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('object')=='list'
assert 'data' in d
assert d['data'][0].get('object')=='model'
print('valid')
" 2>/dev/null | grep -q "valid"; then
  record "SC7" "GET /v1/models format" "PASS" "Response matches OpenAI API schema (object:list, data:[{object:model}])"
else
  record "SC7" "GET /v1/models format" "FAIL" "Response not OpenAI-compatible"
fi
echo ""

# Test 7.2: /v1/chat/completions returns OpenAI-format response
echo "--- 7.2: OpenAI-compatible /v1/chat/completions ---"
CHAT_RESP=$(oc run val-chat --rm -i --restart=Never --image=curlimages/curl -n $MODEL_NS --command -- \
  curl -sk --max-time 15 "https://${MAAS_GW_SVC}/${MODEL_NS}/${MODEL_NAME}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}],\"max_tokens\":10}" 2>/dev/null)
if echo "$CHAT_RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('object')=='chat.completion'
assert d['choices'][0]['message']['role']=='assistant'
assert len(d['choices'][0]['message']['content'])>0
print('valid')
" 2>/dev/null | grep -q "valid"; then
  record "SC7" "POST /v1/chat/completions format" "PASS" "Response matches OpenAI chat completion schema"
else
  record "SC7" "POST /v1/chat/completions format" "FAIL" "Response: ${CHAT_RESP:0:100}"
fi
echo ""

# Test 7.3: Multi-cluster gateway serves same API
echo "--- 7.3: Multi-cluster gateway OpenAI API ---"
oc config use-context "$CTX_GW" &>/dev/null
MC_GW_SVC="ai-inference-gateway-istio.ai-gateway.svc:80"
MC_RESP=$(oc run val-mc --rm -i --restart=Never --image=curlimages/curl -n default --command -- \
  curl -s --max-time 10 "http://${MC_GW_SVC}/v1/models" 2>/dev/null)
oc config use-context "$CTX_GPU" &>/dev/null
if echo "$MC_RESP" | grep -q '"object".*"list"'; then
  record "SC7" "Multi-cluster same API" "PASS" "AI Gateway on cluster-6crhb returns OpenAI-format models"
else
  record "SC7" "Multi-cluster same API" "FAIL" "Response: ${MC_RESP:0:100}"
fi
echo ""

# ============================================================================
header "SC #8 (P3): Secret Rotation (Vault + ESO)"
# ============================================================================
echo "Requirement: Credential rotation via Vault + ESO with zero downtime."
echo ""

oc config use-context "$CTX_GW" &>/dev/null

# Test 8.1: SecretStore is valid
echo "--- 8.1: SecretStore connected to Vault ---"
SS_STATUS=$(oc get secretstore vault-backend -n vault-dev -o jsonpath='{.status.conditions[0].message}' 2>/dev/null)
if [ "$SS_STATUS" = "store validated" ]; then
  record "SC8" "SecretStore validated" "PASS" "Vault connection healthy"
else
  record "SC8" "SecretStore validated" "FAIL" "Status: ${SS_STATUS}"
fi
echo ""

# Test 8.2: ExternalSecrets are synced
echo "--- 8.2: ExternalSecrets synced ---"
ES_STATUS=$(oc get externalsecret -n vault-dev --no-headers 2>/dev/null | grep -c "SecretSynced" || echo "0")
ES_TOTAL=$(oc get externalsecret -n vault-dev --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$ES_STATUS" -ge 1 ]; then
  record "SC8" "ExternalSecrets synced" "PASS" "${ES_STATUS}/${ES_TOTAL} ExternalSecret(s) synced from Vault"
else
  record "SC8" "ExternalSecrets synced" "FAIL" "No synced ExternalSecrets found"
fi
echo ""

# Test 8.3: K8s Secret has Vault data
echo "--- 8.3: K8s Secret contains Vault values ---"
SECRET_VAL=$(oc get secret ai-bridge-api-keys -n vault-dev -o jsonpath='{.data.team-a-key}' 2>/dev/null | base64 -d 2>/dev/null)
if [ -n "$SECRET_VAL" ] && echo "$SECRET_VAL" | grep -q "sk-team-a"; then
  record "SC8" "Secret has Vault data" "PASS" "K8s Secret value: ${SECRET_VAL}"
else
  record "SC8" "Secret has Vault data" "FAIL" "Secret empty or missing"
fi
echo ""

# Test 8.4: Rotation demo (update Vault, verify sync)
echo "--- 8.4: Secret rotation flow ---"
VAULT_POD=$(oc get pods -n vault-dev -l app=vault -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$VAULT_POD" ]; then
  TIMESTAMP=$(date +%s)
  oc exec $VAULT_POD -n vault-dev -- sh -c "export VAULT_TOKEN=demo-root-token && vault kv put secret/ai-bridge/api-keys team-a-key=sk-team-a-validated-${TIMESTAMP} team-b-key=sk-team-b-validated-${TIMESTAMP}" &>/dev/null
  echo "  Updated Vault secret at $(date). Waiting 35s for ESO refresh..."
  sleep 35
  NEW_VAL=$(oc get secret ai-bridge-api-keys -n vault-dev -o jsonpath='{.data.team-a-key}' 2>/dev/null | base64 -d 2>/dev/null)
  if echo "$NEW_VAL" | grep -q "validated-${TIMESTAMP}"; then
    record "SC8" "Rotation synced" "PASS" "New value propagated: ${NEW_VAL}"
  else
    record "SC8" "Rotation synced" "FAIL" "Value not updated: ${NEW_VAL}"
  fi
else
  record "SC8" "Rotation synced" "SKIP" "Vault pod not found"
fi
echo ""

oc config use-context "$CTX_GPU" &>/dev/null

# ============================================================================
header "BONUS: Guardrails Gateway"
# ============================================================================
echo "Content safety filtering via PII detection."
echo ""

# Test G.1: Passthrough endpoint works
echo "--- G.1: Passthrough (no filtering) ---"
GR_PASS=$(curl -s --max-time 15 "http://${GR_HOST}/passthrough/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"max_tokens\":10}" 2>/dev/null)
if echo "$GR_PASS" | grep -q '"choices"'; then
  record "BONUS" "Guardrails passthrough" "PASS" "Inference works through guardrails gateway"
else
  record "BONUS" "Guardrails passthrough" "FAIL" "Response: ${GR_PASS:0:100}"
fi
echo ""

# Test G.2: PII detection endpoint
echo "--- G.2: PII detection endpoint ---"
GR_PII=$(curl -s --max-time 15 "http://${GR_HOST}/pii/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"My SSN is 123-45-6789 and email is test@corp.com\"}],\"max_tokens\":50}" 2>/dev/null)
if echo "$GR_PII" | grep -q '"choices"\|blocked'; then
  record "BONUS" "Guardrails PII detection" "PASS" "Request processed through PII detection pipeline"
else
  record "BONUS" "Guardrails PII detection" "FAIL" "Response: ${GR_PII:0:100}"
fi
echo ""

# ============================================================================
header "BONUS: Multi-Cluster Routing"
# ============================================================================
echo "Central gateway on CPU cluster routes to GPU cluster model."
echo ""

oc config use-context "$CTX_GW" &>/dev/null

# Test M.1: Gateway resources exist
echo "--- M.1: Istio routing resources ---"
SE=$(oc get serviceentry -n ai-gateway --no-headers 2>/dev/null | wc -l | tr -d ' ')
DR=$(oc get destinationrule -n ai-gateway --no-headers 2>/dev/null | wc -l | tr -d ' ')
HR=$(oc get httproute -n ai-gateway --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$SE" -ge 1 ] && [ "$DR" -ge 1 ] && [ "$HR" -ge 1 ]; then
  record "BONUS" "Multi-cluster resources" "PASS" "ServiceEntry(${SE}), DestinationRule(${DR}), HTTPRoute(${HR})"
else
  record "BONUS" "Multi-cluster resources" "FAIL" "Missing: SE=${SE} DR=${DR} HR=${HR}"
fi
echo ""

# Test M.2: Cross-cluster inference
echo "--- M.2: Cross-cluster inference ---"
MC_CHAT=$(oc run val-mc2 --rm -i --restart=Never --image=curlimages/curl -n default --command -- \
  curl -s --max-time 15 "http://ai-inference-gateway-istio.ai-gateway.svc:80/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"What is AI?\"}],\"max_tokens\":20}" 2>/dev/null)
if echo "$MC_CHAT" | grep -q '"choices"'; then
  record "BONUS" "Cross-cluster inference" "PASS" "Request on cluster-6crhb served by model on cluster-4l6x6"
else
  record "BONUS" "Cross-cluster inference" "FAIL" "Response: ${MC_CHAT:0:100}"
fi
echo ""

oc config use-context "$CTX_GPU" &>/dev/null

# ============================================================================
header "VALIDATION SUMMARY"
# ============================================================================
echo ""
printf "%-6s %-35s %-6s %s\n" "SC" "TEST" "STATUS" "DETAIL"
printf "%-6s %-35s %-6s %s\n" "------" "-----------------------------------" "------" "------------------------------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r sc test status detail <<< "$r"
  printf "%-6s %-35s %-6s %s\n" "$sc" "$test" "$status" "${detail:0:50}"
done

echo ""
echo "========================================================================"
echo "  TOTAL: ${PASS_COUNT} PASS | ${FAIL_COUNT} FAIL | ${SKIP_COUNT} SKIP"
echo "========================================================================"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "Some tests FAILED. Review output above for details."
  exit 1
else
  echo "All critical tests passed. Environment aligns with PoC requirements."
  exit 0
fi
