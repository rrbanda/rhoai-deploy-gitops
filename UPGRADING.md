# Upgrading Between RHOAI Versions

This guide explains how to upgrade your OpenShift AI deployment to a newer version.

---

## General Upgrade Strategy

Since this repo uses GitOps, upgrades are performed by:
1. Updating your `cluster-config.yaml` (or the manifests) in Git
2. Pushing to your repository
3. ArgoCD automatically applies the changes

**There is no downtime for most upgrades.** The RHOAI operator handles rolling updates.

---

## Upgrading from 3.4 to 3.5

### What Changed in 3.5

| Change | Impact |
|--------|--------|
| DSC API: `v1` → `v2` | Must update `apiVersion` in DSC manifests |
| `llamastackoperator` → `ogx` | Old field deprecated, new one required |
| `kueue.managementState` | Must be `Unmanaged` (managed by own operator) |
| HardwareProfile API group | `dashboard.opendatahub.io` → `infrastructure.opendatahub.io` |
| Service Mesh | v2 → v3 (`servicemeshoperator3`) |
| New components | `aigateway`, `batchGateway`, `mlflowoperator`, `sparkoperator`, `trainer` |

### Step-by-Step Upgrade

#### 1. Update the RHOAI operator channel

In `components/operators/rhoai-operator/patch-channel.yaml`:
```yaml
- op: replace
  path: /spec/channel
  value: beta    # or "fast" for GA releases
```

#### 2. Update the DataScienceCluster

In `components/instances/rhoai-instance/base/datasciencecluster.yaml`:

```diff
- apiVersion: datasciencecluster.opendatahub.io/v1
+ apiVersion: datasciencecluster.opendatahub.io/v2
  kind: DataScienceCluster
  ...
  spec:
    components:
+     aigateway:
+       managementState: Managed
+       batchGateway:
+         managementState: Managed
+     llamastackoperator:
+       managementState: Removed
+     ogx:
+       managementState: Managed
+     mlflowoperator:
+       managementState: Managed
+     sparkoperator:
+       managementState: Managed
+     trainer:
+       managementState: Managed
      kueue:
-       managementState: Managed
+       managementState: Unmanaged
```

#### 3. Install new prerequisite operators

Add these directories:
- `components/operators/cma-operator/` — Custom Metrics Autoscaler
- `components/operators/lws/` — LeaderWorkerSet

#### 4. Update Kueue operator channel

In `components/operators/kueue-operator/subscription.yaml`:
```diff
- channel: stable-v1.2
+ channel: stable-v1.4
```

#### 5. Update Service Mesh

In `components/operators/servicemesh/subscription.yaml`:
```diff
- name: servicemeshoperator
+ name: servicemeshoperator3
  channel: stable
```

#### 6. Push and verify

```bash
git add -A && git commit -m "Upgrade to RHOAI 3.5" && git push

# Monitor the upgrade
watch oc get datasciencecluster default-dsc \
  -o jsonpath='{.status.phase}'
```

### Known Issues During 3.4 → 3.5 Upgrade

| Issue | Solution |
|-------|----------|
| `Managed is no longer supported` for kueue | Set `kueue.managementState: Unmanaged` |
| TrustyAI `immutable field` error | Delete the `trustyai-service-operator-controller-manager` deployment |
| `batchGateway in body must be of type object: "null"` | Use `Replace=true` sync option on DSC app |
| AI Gateway operator OOMKilled | Increase memory limit to 1Gi (PostSync hook handles this) |

---

## Pinning to a Specific Version

If you want to stay on a specific RHOAI version and not auto-upgrade:

```bash
# Pin to a tagged release
./scripts/configure.sh --repo <your-url> --branch v3.5.0-ea2

# Or set installPlanApproval to Manual in the RHOAI subscription
```

---

## Rolling Back

If an upgrade fails:

```bash
# Revert your Git changes
git revert HEAD
git push

# ArgoCD will automatically roll back the cluster state
```

For critical issues, you can also:
```bash
# Manually point ArgoCD to the previous tag
oc patch applicationset cluster-operators -n openshift-gitops \
  --type=json -p '[{"op":"replace","path":"/spec/generators/0/git/revision","value":"v3.4.0"}]'
```
