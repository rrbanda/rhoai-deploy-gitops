# Use Cases

This section shows how to deploy complete AI applications on top of RHOAI using the GitOps patterns established in this repository. Each use case is self-contained and demonstrates practical deployment patterns.

## How Use Cases Are Structured

The repository separates **models** (individual model deployments) from **services** (applications that consume models):

```
usecases/
├── models/                 # One directory per model
│   └── <model-name>/
│       ├── manifests/      # ServingRuntime, InferenceService, PVC, download Job
│       └── profiles/
│           └── tier1-minimal/  # Auto-discovered by cluster-models AppSet
└── services/               # Application services
    └── <service-name>/
        ├── manifests/      # Deployments, Routes, ConfigMaps
        └── profiles/
            └── tier1-minimal/  # Auto-discovered by cluster-services AppSet
```

## Auto-Discovery

Use cases are automatically discovered and deployed by ArgoCD ApplicationSets:

- **Models:** Any directory matching `usecases/models/*/profiles/tier1-minimal/` becomes an ArgoCD Application named `model-<dirname>`
- **Services:** Any directory matching `usecases/services/*/profiles/tier1-minimal/` becomes an ArgoCD Application named `service-<dirname>`

To add a new use case, create the directory structure, push to Git, and ArgoCD creates the Application automatically.

## Available Models

| Model | Description | GPU Required | Namespace | Enablement |
|-------|------------|-------------|-----------|------------|
| **gemma2-9b-fp8** | Gemma 2 9B FP8 quantized model — general-purpose instruct | 1x NVIDIA L4/A10G (24GB VRAM) | `models-as-a-service` | `./scripts/configure.sh enable-model gemma2-9b-fp8` |
| **orchestrator-8b** | Orchestrator 8B — multi-agent orchestration router | 1x NVIDIA L4/A10G (24GB VRAM) | `models-as-a-service` | `./scripts/configure.sh enable-model orchestrator-8b` |
| **qwen-math-7b** | Qwen Math 7B — specialized mathematical reasoning | 1x NVIDIA L4/A10G (24GB VRAM) | `models-as-a-service` | `./scripts/configure.sh enable-model qwen-math-7b` |
| **qwen25-7b-instruct** | Qwen 2.5 7B Instruct — multilingual reasoning and chat | 1x NVIDIA L4/A10G (24GB VRAM) | `llm-inference` | `./scripts/configure.sh enable-model qwen25-7b-instruct` |
| **gpt-oss-120b** | GPT-OSS 120B — large-scale multi-GPU model (requires TP/PP) | 4x NVIDIA A100 80GB (tensor parallelism) | `models-as-a-service` | `./scripts/configure.sh enable-model gpt-oss-120b` |

## Available Services

| Service | Description | Requires Customization | Namespace | Enablement |
|---------|------------|----------------------|-----------|------------|
| **ai-gateway** | Kuadrant AI Gateway — unified API gateway with OIDC auth and rate limiting | Yes — update `service-entry.yaml` and `auth-policy.yaml` with your cluster's inference and Keycloak URLs | `ai-gateway` | `./scripts/configure.sh enable-service ai-gateway` |
| **guardrails-gateway** | Content safety guardrails gateway — input/output filtering for LLMs | Yes — update `VLLM_URL` in `deployment.yaml` and `configmap.yaml` to match your cluster's model serving endpoint | `guardrails-gateway` | `./scripts/configure.sh enable-service guardrails-gateway` |
| **genai-toolbox** | GenAI Toolbox — tool calling infrastructure for function-calling agents | No | `genai-toolbox` | `./scripts/configure.sh enable-service genai-toolbox` |
| **llamastack** | LlamaStack distribution — Meta reference inference stack with guardrails | No | `llamastack` | `./scripts/configure.sh enable-service llamastack` |
| **llm-d-epp** | llm-d Endpoint Picker Pod — intelligent request routing with prefix cache and load scoring | No | `llm-d-epp` | `./scripts/configure.sh enable-service llm-d-epp` |
| **rhokp** | Red Hat OpenShift Knowledge Platform — RAG-as-a-Service with document ingestion | No | `rhokp` | `./scripts/configure.sh enable-service rhokp` |
| **toolorchestra-app** | ToolOrchestra — multi-agent orchestration platform with training pipelines | No | `toolorchestra` | `./scripts/configure.sh enable-service toolorchestra-app` |

See [GenAI Toolbox](genai-toolbox.md) for a detailed deployment guide.

!!! info "LlamaStack → OGX (OpenGenX)"
    The `llamastackoperator` DSC component has been superseded by **OGX (OpenGenX)**. The `ogx` component is the active replacement. Set `llamastackoperator: Removed` and `ogx: Managed` in your DSC. The `usecases/services/llamastack/` directory still contains manifests for deploying a LlamaStack application instance, but the underlying operator is now OGX.

## Adding a New Model

1. Create the directory structure:
   ```
   usecases/models/my-model/
   ├── manifests/
   │   ├── kustomization.yaml
   │   ├── namespace.yaml
   │   ├── serving-runtime.yaml
   │   ├── inference-service.yaml
   │   └── download-job.yaml    # Optional: pre-download weights
   └── profiles/
       └── tier1-minimal/
           └── kustomization.yaml   # References ../../manifests/
   ```

2. Push to Git. The `cluster-models` ApplicationSet auto-discovers it.

### Key Patterns for Model Deployments

**Sync waves** ensure correct ordering:

| Wave | Resources | Purpose |
|------|-----------|---------|
| -1 | Namespace, PVC, ServingRuntime | Infrastructure first |
| 0 | Download Job | Fetch model weights to PVC |
| 1 | InferenceService | Start serving after download completes |

**Download job idempotency:** Jobs check for a `.download_complete` marker before downloading. This makes them safe to re-run without re-downloading.

**No TTL on jobs:** Download jobs have no `ttlSecondsAfterFinished`. Completed jobs persist so ArgoCD shows them as Synced/Healthy without attempting recreation.

## Adding a New Service

1. Create the directory structure:
   ```
   usecases/services/my-service/
   ├── manifests/
   │   ├── base/
   │   │   ├── kustomization.yaml
   │   │   └── namespace.yaml
   │   └── services/
   │       └── my-app/
   │           ├── deployment.yaml
   │           └── route.yaml
   └── profiles/
       └── tier1-minimal/
           └── kustomization.yaml
   ```

2. Push to Git. The `cluster-services` ApplicationSet auto-discovers it.

## Excluding a Use Case

To include a use case in the repo without deploying it, add it to the ApplicationSet's `exclude` list:

```yaml
# In cluster-models-appset.yaml or cluster-services-appset.yaml
spec:
  generators:
    - git:
        directories:
          - path: usecases/models/*/profiles/tier1-minimal
          - path: usecases/models/my-excluded-model/profiles/tier1-minimal
            exclude: true
```

The manifests remain in Git (ready for future use) but ArgoCD does not create an Application for them.

!!! warning "Deploy models before services"
    Services typically depend on model endpoints being reachable. In manual deployment, deploy all required models and wait for them to become Ready before deploying services. In GitOps mode, ArgoCD deploys both in parallel; services will self-heal once their model dependencies are ready.
