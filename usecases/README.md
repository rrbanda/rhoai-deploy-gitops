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

| Service | Namespace | Description |
|---------|-----------|-------------|
| **genai-toolbox** | genai-toolbox | MCP Toolbox for Databases (PostgreSQL) |
| **llamastack** | llamastack | LlamaStack distribution with PostgreSQL backend |
| **toolorchestra-app** | orchestrator-rhoai | ToolOrchestra UI for multi-model orchestration |

## Adding a New Model

1. Copy any model folder as a template: `cp -r usecases/models/gpt-oss-120b usecases/models/my-model`
2. Update the 6 YAML files with your model's details (namespace, storageUri, GPU requirements)
3. Push to Git -- the `cluster-models` ApplicationSet auto-discovers it

## Deploying / Removing

- **Deploy:** Model's `profiles/tier1-minimal/` directory exists -> ArgoCD auto-creates app
- **Remove:** Delete `profiles/tier1-minimal/` or the entire model folder -> ArgoCD prunes resources

## Manual Deployment

```bash
oc apply -k usecases/models/gpt-oss-120b/profiles/tier1-minimal/
```
