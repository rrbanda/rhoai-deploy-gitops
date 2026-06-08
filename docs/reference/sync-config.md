# Sync Configuration

The ArgoCD ApplicationSets use production-grade sync options validated through testing.

## Sync Options

| Option | Purpose |
|--------|---------|
| `ServerSideApply=true` | Handles large CRDs (DSC, InferenceService, ClusterPolicy) and prevents annotation size limits |
| `SkipDryRunOnMissingResource=true` | Allows retry-based convergence when CRDs don't exist yet |
| `RespectIgnoreDifferences=true` | Honors configured `ignoreDifferences` rules |

## ignoreDifferences Rules

**OLM Subscriptions** -- Prevents perpetual drift on `.status` and `.spec.startingCSV`:

```yaml
ignoreDifferences:
  - group: operators.coreos.com
    kind: Subscription
    jsonPointers:
      - /spec/startingCSV
      - /status
```

**ClusterPolicy, NodeFeatureDiscovery** (instances ApplicationSet) -- Prevents drift from operator-managed status:

```yaml
ignoreDifferences:
  - group: nvidia.com
    kind: ClusterPolicy
    jsonPointers:
      - /status
  - group: nfd.openshift.io
    kind: NodeFeatureDiscovery
    jsonPointers:
      - /status
```

**DataScienceCluster** -- Prevents drift on `/status` and operator-managed component fields:

```yaml
ignoreDifferences:
  - group: datasciencecluster.opendatahub.io
    kind: DataScienceCluster
    jsonPointers:
      - /status
      - /spec/components/dashboard
      - /spec/components/kserve
      - /spec/components/ray
      - /spec/components/trainingoperator
      - /spec/components/modelmeshserving
      - /spec/components/codeflare
      - /spec/components/datasciencepipelines
      - /spec/components/workbenches
      - /spec/components/modelregistry
      - /spec/components/trustyai
```

## Retry Policies

| Layer | Max Retries | Backoff | Max Duration |
|-------|------------|---------|-------------|
| Operators | 5 | 30s (factor 2) | 5 min |
| Instances | 10 | 60s (factor 2) | 10 min |

The higher retry count for instances gives operators time to install their CRDs before ArgoCD attempts to apply instance resources.

## RHOAI 3.4 Specifics

| Setting | Value | Notes |
|---------|-------|-------|
| RHOAI channel | `fast-3.x` | Required for 3.x releases |
| DSC API | `datasciencecluster.opendatahub.io/v2` | Stable API for 3.4 |
| Kueue | `Unmanaged` in DSC | Red Hat Build of Kueue Operator manages it separately |
| JobSet | Standalone operator | Required for Kubeflow Trainer v2 |
| GPU Operator | Requires `spec.daemonsets` and `spec.dcgm` | Validated with v25.x |
| Kueue instance | Requires `spec.config.integrations.frameworks` | List of supported job frameworks |
