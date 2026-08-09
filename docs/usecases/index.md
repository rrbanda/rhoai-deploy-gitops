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

## Auto-Discovery (Opt-In)

Use cases are discovered by ArgoCD ApplicationSets via the [App-of-Apps pattern](../concepts/app-of-apps.md), but deployment is **opt-in**. Pushing a new directory alone does **not** deploy it — you must explicitly enable it:

```bash
./scripts/configure.sh enable-model <name>
# or
./scripts/configure.sh enable-service <name>
```

This sets `"enabled": "true"` in the use case's `config.json`, which is the gate the ApplicationSet uses to create the Application. See [Configuration > Deploying Models and Services](../configuration.md#deploying-models-and-services-opt-in-pattern) for full details.

## Available Models and Services

For the full catalog of available models and services (with GPU requirements, namespaces, and enable commands), see the [Configuration guide](../configuration.md#available-models).

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

2. Enable the model:
   ```bash
   ./scripts/configure.sh enable-model my-model
   ```
   This creates `config.json` with `"enabled": "true"` in the model's directory.

3. Push to Git. The `cluster-models` ApplicationSet discovers it via the enabled `config.json`.

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

2. Enable the service:
   ```bash
   ./scripts/configure.sh enable-service my-service
   ```

3. Push to Git. The `cluster-services` ApplicationSet discovers it via the enabled `config.json`.

## Disabling a Use Case

To include a use case in the repo without deploying it, set `"enabled": "false"` in its `config.json` (or run the disable command):

```bash
./scripts/configure.sh disable-model <name>
# or
./scripts/configure.sh disable-service <name>
```

This sets `"enabled": "false"` in `config.json`. The manifests remain in Git (ready for future use) but the ApplicationSet does not create an Application for them because the git file generator only matches directories where `config.json` contains `"enabled": "true"`.

!!! warning "Deploy models before services"
    Services typically depend on model endpoints being reachable. In manual deployment, deploy all required models and wait for them to become Ready before deploying services. In GitOps mode, ArgoCD deploys both in parallel; services will self-heal once their model dependencies are ready.
