# AutoRAG Workload Layer

Deploys an OGX Server + Pipeline Server (with AutoRAG enabled) via GitOps.
This is the **workload layer** -- it creates instances of CRDs that the
platform layer (Helm chart) already installed.

## What the Helm chart already provides (DO NOT duplicate)

- OGX Operator (managementState: Managed in DSC)
- AIPipelines Operator (managementState: Managed in DSC)
- NFD + GPU Operator (OGX dependencies)
- Dashboard with AutoRAG/GenAI Studio UI
- All operator Subscriptions, OperatorGroups, operator Namespaces

## What this workload layer creates

| Resource | Kind | Purpose |
|---|---|---|
| Namespace `autorag` | Namespace | Dedicated namespace for RAG workloads |
| `autorag-ogx` | OGXServer | RAG backbone: inference, embedding, vector I/O, file processing |
| `dspa` | DataSciencePipelinesApplication | Pipeline server with AutoRAG/AutoML enabled |
| `autorag-ogx-config` | ConfigMap | OGX provider config (Gemini, sentence-transformers, Milvus) |
| `llm-api-secret` | SealedSecret | LLM API key (encrypted, safe in Git) |
| `autorag-s3-connection` | SealedSecret | S3 credentials for pipeline artifacts (encrypted, safe in Git) |

## Prerequisites

- Platform layer deployed (Helm chart with OGX, AIPipelines Managed)
- Sealed Secrets operator running (deployed by bootstrap)
- Milvus deployed in `milvus` namespace (external to RHOAI)
- `kubeseal` CLI installed locally

## Setup

### 1. Seal the LLM API key

```bash
# Copy template and fill in your API key
cp templates/llm-api-secret.yaml.template /tmp/llm-secret.yaml
# Edit /tmp/llm-secret.yaml: replace REPLACE_WITH_LLM_API_KEY

# Fetch cluster's sealing cert
kubeseal --fetch-cert --controller-namespace sealed-secrets > /tmp/pub-cert.pem

# Seal
kubeseal --format yaml --cert /tmp/pub-cert.pem \
  < /tmp/llm-secret.yaml \
  > sealed-llm-api-secret.yaml
```

### 2. Seal the S3 connection

```bash
cp templates/s3-connection-secret.yaml.template /tmp/s3-secret.yaml
# Edit /tmp/s3-secret.yaml: fill in all REPLACE_WITH_ values

kubeseal --format yaml --cert /tmp/pub-cert.pem \
  < /tmp/s3-secret.yaml \
  > sealed-s3-connection-secret.yaml
```

### 3. Configure the DSPA

Edit `dspa.yaml` and replace:
- `REPLACE_WITH_BUCKET_NAME` with your S3 bucket name
- `REPLACE_WITH_S3_HOST` with your S3 endpoint hostname

### 4. Configure OGX (optional)

Edit `ogx-config.yaml` if you need:
- A different LLM provider (replace Gemini with OpenAI, etc.)
- A different Milvus endpoint
- Additional models

### 5. Commit and push

```bash
git add sealed-*.yaml dspa.yaml ogx-config.yaml
git commit -m "Configure AutoRAG workload with sealed credentials"
git push
```

ArgoCD deploys the SealedSecrets, Sealed Secrets controller decrypts them
into real Secrets, then OGXServer and DSPA start using them.

### 6. Clean up plaintext

```bash
rm /tmp/llm-secret.yaml /tmp/s3-secret.yaml /tmp/pub-cert.pem
```

## Endpoints After Deployment

| Service | URL |
|---|---|
| OGX API (in-cluster) | `http://autorag-ogx-service.autorag.svc:8321` |
| OGX `/v1/models` | List available models |
| OGX `/v1/chat/completions` | LLM inference (OpenAI-compatible) |
| OGX `/v1/embeddings` | Text embeddings |
| AutoRAG UI | RHOAI Dashboard > Gen AI Studio > AutoRAG |

## For local development

```bash
oc port-forward svc/autorag-ogx-service -n autorag 8321:8321
# Then use http://localhost:8321
```
