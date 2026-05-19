#!/bin/bash
# Stage A Validation: AI Bridge Foundation
# Validates OpenAI-compatible API access through the MaaS gateway
set -euo pipefail

MAAS_GATEWAY="${MAAS_GATEWAY:-$(oc get gateway maas-default-gateway -n openshift-ingress -o jsonpath='{.status.addresses[0].value}')}"
MODEL_NAME="${MODEL_NAME:-gemma2-9b-fp8}"
TOKEN="${API_TOKEN:-$(oc whoami -t)}"

echo "=== Stage A: AI Bridge Foundation Validation ==="
echo "Gateway: ${MAAS_GATEWAY}"
echo "Model: ${MODEL_NAME}"
echo ""

echo "--- Test 1: List Models (GET /v1/models) ---"
MODELS_RESPONSE=$(curl -sk \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://${MAAS_GATEWAY}/v1/models")
echo "${MODELS_RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "${MODELS_RESPONSE}"

MODEL_COUNT=$(echo "${MODELS_RESPONSE}" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo "0")
if [ "${MODEL_COUNT}" -gt 0 ]; then
  echo "PASS: ${MODEL_COUNT} model(s) available"
else
  echo "FAIL: No models returned"
  exit 1
fi
echo ""

echo "--- Test 2: Chat Completion (POST /v1/chat/completions) ---"
CHAT_RESPONSE=$(curl -sk \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"What is 2+2? Answer in one word.\"}],
    \"max_tokens\": 10
  }" \
  "https://${MAAS_GATEWAY}/v1/chat/completions")
echo "${CHAT_RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "${CHAT_RESPONSE}"

CHOICE=$(echo "${CHAT_RESPONSE}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('choices',[{}])[0].get('message',{}).get('content',''))" 2>/dev/null || echo "")
if [ -n "${CHOICE}" ]; then
  echo "PASS: Got completion response"
else
  echo "FAIL: No completion content returned"
  exit 1
fi
echo ""

echo "--- Test 3: API Compatibility (base URL change only) ---"
echo "Validating that standard OpenAI SDK works with only OPENAI_BASE_URL change..."
python3 -c "
import os
os.environ['OPENAI_API_KEY'] = '${TOKEN}'
os.environ['OPENAI_BASE_URL'] = 'https://${MAAS_GATEWAY}/v1'
try:
    from openai import OpenAI
    client = OpenAI(base_url='https://${MAAS_GATEWAY}/v1', api_key='${TOKEN}')
    # Disable SSL verification for self-signed certs
    import httpx
    client = OpenAI(
        base_url='https://${MAAS_GATEWAY}/v1',
        api_key='${TOKEN}',
        http_client=httpx.Client(verify=False)
    )
    models = client.models.list()
    print(f'PASS: OpenAI SDK listed {len(models.data)} model(s)')
except ImportError:
    print('SKIP: openai package not installed (pip install openai)')
except Exception as e:
    print(f'FAIL: {e}')
" 2>/dev/null
echo ""

echo "=== Stage A Validation Complete ==="
