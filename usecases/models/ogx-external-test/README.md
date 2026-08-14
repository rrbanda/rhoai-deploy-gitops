# OGX External Test — Non-GPU Model Use Case

Deploys an [OGX](https://ogx-ai.github.io/docs) (formerly LlamaStack) server on OpenShift AI
that proxies inference to **any external OpenAI-compatible endpoint** — no GPU required.

## What RHOAI manages automatically

The `LlamaStackDistribution` operator (part of RHOAI) handles:

| Component | Managed by |
|-----------|-----------|
| Deployment (OGX server pod) | OGX Operator via `LlamaStackDistribution` CR |
| Service | OGX Operator (`spec.server.containerSpec.port`) |
| Route (TLS) | OGX Operator (`spec.network.exposeRoute: true`) |
| NetworkPolicy | OGX Operator (`spec.network.allowedFrom`) |
| Config volume mount | OGX Operator (`spec.server.userConfig.configMapName`) |

**What we provide:**
- `ConfigMap` with OGX `config.yaml` (provider wiring)
- `Secret` with external provider credentials
- `Namespace`

## What this demonstrates

| Capability | How |
|------------|-----|
| OGX API server (Responses, Tools, Vector IO) | `LlamaStackDistribution` CR managed by OGX operator |
| External model routing (no GPU) | `remote::openai` provider with configurable `base_url` |
| RAG-ready vector store | Inline Milvus + Granite embeddings (CPU only) |
| MCP tool integration | `remote::model-context-protocol` provider |
| OpenAI-compatible API | Same `/v1/chat/completions` and `/v1/responses` surface |
| Agentic orchestration | Server-side tool execution via Responses API |

## Supported external providers

Any OpenAI-compatible endpoint works via `remote::openai`:

| Provider | `base-url` value |
|----------|-----------------|
| OpenAI | `https://api.openai.com/v1` |
| Groq | `https://api.groq.com/openai/v1` |
| Together AI | `https://api.together.xyz/v1` |
| Fireworks | `https://api.fireworks.ai/inference/v1` |
| Any vLLM server | `https://<your-vllm-host>/v1` |

## Configuration

1. Update the Secret in `manifests/credentials-secret.yaml`:
   - `api-key`: Your provider's API key
   - `base-url`: The OpenAI-compatible base URL

2. Enable in `profiles/tier1-minimal/config.json`:
   ```json
   { "enabled": "true" }
   ```

## Testing

Once deployed, access the OGX server via its operator-managed Route:

```bash
# Get the route URL (created automatically by the OGX operator)
OGX_URL=$(oc get route ogx-external-test -n ogx-external-test -o jsonpath='{.spec.host}')

# List available models (auto-discovered from external provider)
curl -s https://${OGX_URL}/v1/models | jq .

# Chat completions (OpenAI-compatible)
curl -s https://${OGX_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "external-openai-compat/<model-id>",
    "messages": [{"role": "user", "content": "Hello from OGX on OpenShift AI"}],
    "max_tokens": 128
  }' | jq .

# Responses API — agentic orchestration with server-side tool execution
curl -s https://${OGX_URL}/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "external-openai-compat/<model-id>",
    "input": "What is Red Hat OpenShift AI?",
    "tools": [{"type": "web_search_preview"}]
  }' | jq .
```

## Resource requirements

| Resource | Request | Limit | Notes |
|----------|---------|-------|-------|
| CPU | 250m | 2 | OGX server only |
| Memory | 512Mi | 4Gi | Includes Milvus in-process |
| GPU | none | none | Model served externally |

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  OpenShift Cluster (RHOAI)                                   │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  ogx-external-test namespace                           │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  LlamaStackDistribution (operator-managed)       │  │  │
│  │  │                                                  │  │  │
│  │  │  OGX Server Pod                                  │  │  │
│  │  │  ├── /v1/chat/completions  (inference)           │  │  │
│  │  │  ├── /v1/responses         (agentic + tools)     │  │  │
│  │  │  ├── /v1/vector_stores     (RAG)                 │  │  │
│  │  │  └── /v1/models            (discovery)           │  │  │
│  │  │                                                  │  │  │
│  │  │  Auto-created: Deployment, Service, Route, NP    │  │  │
│  │  └──────────────────────┬───────────────────────────┘  │  │
│  │                         │                              │  │
│  └─────────────────────────┼──────────────────────────────┘  │
│                            │ remote::openai                   │
└────────────────────────────┼─────────────────────────────────┘
                             │
                             ▼
              ┌────────────────────────┐
              │  External Provider     │
              │  (Groq / OpenAI /      │
              │   Together / vLLM)     │
              └────────────────────────┘
```
