# Use Cases

Each use case is a self-contained AI application deployed on top of the Red Hat OpenShift AI (RHOAI) platform.

## Structure

```
usecases/
└── <app-name>/
    ├── manifests/
    │   ├── base/          # Namespace, RBAC, config, storage, network
    │   ├── serving/       # ServingRuntimes + InferenceServices (one dir per model)
    │   ├── services/      # Application services (deployments, routes)
    │   └── training/      # Training infrastructure + workloads
    └── profiles/
        ├── tier1-minimal/ # Kustomize overlay (ArgoCD auto-discovers this)
        ├── tier2-standard/
        └── tier3-full/
```

## Current Use Cases

| Use Case | Description | Guide |
|----------|------------|-------|
| **ToolOrchestra** | NVIDIA multi-model orchestrator with specialist routing | [ToolOrchestra](toolorchestra.md) |
| **LlamaStack** | Meta's LlamaStack Distribution with agents, RAG, and tool use | [LlamaStack](llamastack.md) |

## Adding a New Use Case

1. Create a new directory under `usecases/`:

    ```
    usecases/my-app/
      manifests/
        base/
          kustomization.yaml
          namespace.yaml
        serving/
          my-model/
        services/
          my-service/
      profiles/
        tier1-minimal/
          kustomization.yaml
    ```

2. The `cluster-usecases` ApplicationSet auto-discovers `usecases/*/profiles/tier1-minimal` directories. Once pushed to Git, `cluster-bootstrap` syncs the AppSet, which generates a new `usecase-<name>` Application automatically.

3. For manual deployment without ArgoCD:

    ```bash
    oc apply -k usecases/my-app/profiles/tier1-minimal/
    ```

!!! warning "Model download jobs"
    For model download jobs, always:

    - Add `nodeSelector: nvidia.com/gpu.present: "true"` to ensure PVCs are provisioned in the GPU availability zone
    - Add `argocd.argoproj.io/sync-wave: "0"` so downloads run before InferenceService (wave 1)
    - Omit `ttlSecondsAfterFinished` so completed jobs persist and ArgoCD doesn't recreate them
