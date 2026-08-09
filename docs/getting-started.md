# Getting Started Guide

This guide walks you through deploying Red Hat OpenShift AI (RHOAI) on your OpenShift cluster using GitOps. No prior ArgoCD experience required.

---

## What You'll Build

By the end of this guide, you'll have:

- ✅ A fully operational AI/ML platform on OpenShift
- ✅ GPU scheduling with fair-share quotas
- ✅ Model serving infrastructure (KServe + vLLM)
- ✅ Distributed training support (Ray + PyTorch)
- ✅ A GitOps pipeline that auto-deploys changes from Git
- ✅ Everything managed declaratively — no manual `oc` commands needed after setup

---

## Prerequisites

### 1. OpenShift Cluster

You need an OpenShift 4.18+ cluster with:
- **Cluster-admin access** (not just project-level)
- **At least 2 worker nodes** (8 CPU, 32 GiB RAM each)
- **A default StorageClass** (check with `oc get sc`)

Don't have a cluster? Options:
- [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) (free, limited)
- [ROSA (AWS)](https://aws.amazon.com/rosa/) — production-grade
- [ARO (Azure)](https://azure.microsoft.com/en-us/products/openshift) — production-grade
- [demo.redhat.com](https://demo.redhat.com) — Red Hat internal

### 2. Command Line Tools

```bash
# Verify oc is installed and you're logged in as cluster-admin
oc version
oc whoami    # Should show a cluster-admin user

# Verify git
git --version
```

### 3. GPU Nodes (Optional)

For model serving and training, you'll want GPU nodes. This guide works without GPUs (workloads will be pending until GPU nodes are available).

---

## Step-by-Step Deployment

### Step 1: Fork the Repository

1. Go to [github.com/rrbanda/rhoai-deploy-gitops](https://github.com/rrbanda/rhoai-deploy-gitops)
2. Click **Fork** (top-right)
3. Clone your fork:

```bash
git clone https://github.com/YOUR_USERNAME/rhoai-deploy-gitops.git
cd rhoai-deploy-gitops
```

> **Why fork?** ArgoCD reads directly from your Git repository. Your fork is your source of truth.

### Step 2: Configure for Your Cluster

Run the setup script with your fork's URL:

```bash
./setup.sh --repo https://github.com/YOUR_USERNAME/rhoai-deploy-gitops.git
```

This updates a single file (`clusters/overlays/dev/cluster-config.yaml`) that tells ArgoCD where to find your manifests.

**What the setup script does:**
- Sets `repoURL` to your fork
- Sets `targetRevision` to `main` (tracks your main branch)
- Sets `rhoaiChannel` to `beta` (for RHOAI 3.5 EA access)
- Sets `rhoaiOverlay` to `full` (deploys all capabilities)

Commit and push:

```bash
git add -A
git commit -m "Configure for my cluster"
git push origin main
```

### Step 3: Install ArgoCD (OpenShift GitOps)

ArgoCD is the engine that keeps your cluster in sync with Git:

```bash
# Install the OpenShift GitOps operator
oc apply -k bootstrap/

# Wait for it to be ready (usually 1-2 minutes)
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
```

> **What is ArgoCD?** It's a Kubernetes-native CD tool that continuously monitors your Git repository and automatically applies any changes to your cluster. Think of it as "infrastructure autopilot."

### Step 4: Deploy Everything

This is the magic command — it bootstraps the entire platform:

```bash
oc apply -k clusters/overlays/dev/
```

**What happens next (automatically):**

1. ArgoCD creates a self-managing `cluster-bootstrap` Application
2. The bootstrap app creates ApplicationSets for operators, instances, models, and services
3. ApplicationSets auto-discover all directories under `components/operators/` and create one ArgoCD Application per operator
4. Same for `components/instances/` — each instance gets its own ArgoCD Application
5. Operators are installed via OLM (Operator Lifecycle Manager)
6. Once operators are ready, instance CRs are created
7. The RHOAI operator sees the DataScienceCluster CR and reconciles all AI/ML components

**Timeline:** Full deployment takes 10-15 minutes. GPU operators are the slowest.

### Step 5: Monitor Progress

Watch ArgoCD applications sync:

```bash
# See all applications and their sync status
watch oc get applications.argoproj.io -n openshift-gitops

# Check the DataScienceCluster health
oc get datasciencecluster default-dsc \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.status}{"\n"}{end}'
```

**Expected final state:** All applications show `Synced / Healthy` and the DSC shows all conditions `True`.

### Step 6: Access the Dashboard

```bash
# Get the RHOAI dashboard URL
oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='{.spec.host}'
```

Open this URL in your browser. You should see the Red Hat OpenShift AI dashboard with all capabilities enabled.

---

## What Just Got Deployed?

| Layer | What | Purpose |
|-------|------|---------|
| Operators | RHOAI, GPU, NFD, Kueue, ServiceMesh, KEDA, LWS, RHCL | Infrastructure |
| Instances | DataScienceCluster, Kueue config, Hardware Profiles | Configuration |
| Platform | KServe, Ray, Pipelines, Model Registry, MLflow, TrustyAI | AI/ML Capabilities |

---

## Common Issues

### ArgoCD app stuck in "Progressing"

Operators take time to install. Wait 5-10 minutes. If still stuck:

```bash
# Check which app is stuck
oc get applications.argoproj.io -n openshift-gitops | grep -v Synced

# Check the operator subscription status
oc get csv -A | grep -i "rhoai\|kueue\|servicemesh"
```

### DSC shows conditions as "False"

The DSC waits for all dependencies. Common causes:
- An operator hasn't finished installing yet
- A required CRD doesn't exist yet (e.g., LeaderWorkerSet)

```bash
# See which condition is False and why
oc get datasciencecluster default-dsc -o json | \
  jq '.status.conditions[] | select(.status=="False") | {type, message}'
```

### "No GPU nodes available"

If you haven't configured GPU nodes, workloads requiring GPUs will be Pending. See `components/instances/gpu-workers/README.md` for setup instructions.

---

## Next Steps

- **Deploy a model:** See `usecases/models/` for ready-to-use model deployments
- **Add GPU nodes:** See the [GPU Infrastructure Guide](gpu-setup/aws.md)
- **Customize:** See [Customization Guide](customization.md)
- **Upgrade:** See [UPGRADING.md](../UPGRADING.md)
