# Use Cases

Model serving and supporting services are organized into two categories for clean GitOps deployment.

## Structure

```
usecases/
├── models/                          # Model serving catalog
│   └── <model-name>/
│       ├── manifests/
│       │   ├── kustomization.yaml
│       │   ├── namespace.yaml
│       │   ├── serving-runtime.yaml
│       │   ├── inference-service.yaml
│       │   ├── service.yaml
│       │   └── route.yaml
│       └── profiles/
│           └── tier1-minimal/       # ArgoCD auto-discovers this
│               └── kustomization.yaml
└── services/                        # Supporting services
    └── <service-name>/
        ├── manifests/...
        └── profiles/
            └── tier1-minimal/
                └── kustomization.yaml
```

## Current Models

| Model | Namespace | GPU | Storage | Description |
|-------|-----------|-----|---------|-------------|
| **gpt-oss-120b** | gpt-oss-120b | 2x L40S | OCI ModelCar | OpenAI GPT-OSS 120B MoE, MXFP4 quantized, Red Hat AI validated |
| **orchestrator-8b** | orchestrator-8b | 1x | PVC (50Gi) | NVIDIA Nemotron-Orchestrator-8B for multi-tool coordination |
| **qwen-math-7b** | qwen-math-7b | 1x | PVC (30Gi) | Qwen2.5-Math-7B-Instruct math specialist |

## Current Services

| Service | Namespace | Model Dependencies | Description |
|---------|-----------|-------------------|-------------|
| **toolorchestra-app** | orchestrator-rhoai | orchestrator-8b, qwen-math-7b | ToolOrchestra UI for multi-model orchestration |
| **llamastack** | llamastack | orchestrator-8b | LlamaStack distribution with PostgreSQL backend |
| **genai-toolbox** | genai-toolbox | None (uses llamastack's PostgreSQL) | MCP Toolbox for Databases (PostgreSQL) |

> **Deploy models before services.** Services depend on model endpoints being reachable. When deploying manually, deploy all required models and wait for them to become Ready before deploying services.

## Adding a New Model

1. Copy any model folder as a template: `cp -r usecases/models/gpt-oss-120b usecases/models/my-model`
2. Update the YAML files with your model's details (namespace, storageUri, GPU requirements)
3. Create `profiles/tier1-minimal/kustomization.yaml` referencing the manifests
4. Push to Git -- the `cluster-models` ApplicationSet auto-discovers it

## Adding a New Service

1. Create `usecases/services/<name>/manifests/base/` with namespace and RBAC
2. Add service-specific manifests under `manifests/`
3. Create `profiles/tier1-minimal/kustomization.yaml` referencing the manifests
4. Push to Git -- the `cluster-services` ApplicationSet auto-discovers it

## Deploying / Removing

- **Deploy:** A `profiles/tier1-minimal/` directory exists -> ArgoCD auto-creates app
- **Remove:** Delete `profiles/tier1-minimal/` or the entire folder -> ArgoCD prunes resources

## Manual Deployment

```bash
# Models (deploy first)
oc apply -k usecases/models/orchestrator-8b/profiles/tier1-minimal/
oc apply -k usecases/models/qwen-math-7b/profiles/tier1-minimal/

# Services (deploy after models are Ready)
oc apply -k usecases/services/toolorchestra-app/profiles/tier1-minimal/
```
