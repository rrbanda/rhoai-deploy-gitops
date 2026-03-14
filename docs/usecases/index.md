# Use Cases

Each use case is a self-contained AI application deployed on top of the Red Hat OpenShift AI (RHOAI) platform.

## Structure

The repository separates **models** (individual model deployments) from **services** (applications that consume models):

```
usecases/
├── models/                 # One directory per model
│   └── <model-name>/
│       ├── manifests/      # ServingRuntime, InferenceService, PVC, download Job
│       └── profiles/
│           └── tier1-minimal/  # Kustomize overlay (auto-discovered by cluster-models AppSet)
└── services/               # Application services
    └── <service-name>/
        ├── manifests/
        │   ├── base/       # Namespace, RBAC, config, network
        │   ├── services/   # Deployments, Routes
        │   └── training/   # Training infrastructure + workloads
        └── profiles/
            └── tier1-minimal/  # Kustomize overlay (auto-discovered by cluster-services AppSet)
```

## Current Models

| Model | Description |
|-------|------------|
| **orchestrator-8b** | NVIDIA Nemotron-Orchestrator-8B for multi-tool coordination |
| **qwen-math-7b** | Qwen2.5-Math-7B-Instruct math specialist |
| **gpt-oss-120b** | OpenAI GPT-OSS 120B MoE (MXFP4, Red Hat AI validated ModelCar) |

## Current Services

| Service | Description | Model Dependencies | Guide |
|---------|------------|-------------------|-------|
| **toolorchestra-app** | NVIDIA ToolOrchestra UI for multi-model orchestration | orchestrator-8b, qwen-math-7b | [ToolOrchestra](toolorchestra.md) |
| **llamastack** | Meta's LlamaStack Distribution with agents, RAG, and tool use | orchestrator-8b | [LlamaStack](llamastack.md) |
| **genai-toolbox** | GenAI Toolbox MCP Server for database tools | None (uses llamastack's PostgreSQL) | [GenAI Toolbox](genai-toolbox.md) |

!!! warning "Deploy models before services"
    Services depend on model endpoints being reachable. When deploying manually, deploy all required models and wait for them to become Ready before deploying services. In GitOps mode, both `cluster-models` and `cluster-services` ApplicationSets deploy in parallel, so models typically become ready before services finish initializing.

## Adding a New Model

1. Create a directory under `usecases/models/`:

    ```
    usecases/models/my-model/
      manifests/
        kustomization.yaml
        serving-runtime.yaml
        inference-service.yaml
      profiles/
        tier1-minimal/
          kustomization.yaml
    ```

2. The `cluster-models` ApplicationSet auto-discovers `usecases/models/*/profiles/tier1-minimal` directories. Push to Git and a new `model-<name>` Application is created automatically.

## Adding a New Service

1. Create a directory under `usecases/services/`:

    ```
    usecases/services/my-service/
      manifests/
        base/
          kustomization.yaml
          namespace.yaml
        services/
          my-service/
      profiles/
        tier1-minimal/
          kustomization.yaml
    ```

2. The `cluster-services` ApplicationSet auto-discovers `usecases/services/*/profiles/tier1-minimal` directories. Push to Git and a new `service-<name>` Application is created automatically.

!!! warning "Model download jobs"
    For model download jobs, always:

    - Add `argocd.argoproj.io/sync-wave: "-1"` to PVCs so they bind before download Jobs
    - Add `argocd.argoproj.io/sync-wave: "0"` so downloads run before InferenceService (wave 1)
    - Omit `ttlSecondsAfterFinished` so completed jobs persist and ArgoCD doesn't recreate them
