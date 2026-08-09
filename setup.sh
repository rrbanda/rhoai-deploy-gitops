#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# setup.sh — Configure this repository for your cluster
# ─────────────────────────────────────────────────────────────────────────────
# After forking this repo, run this script to point all ArgoCD applications
# at your fork. It updates a single ConfigMap that drives everything.
#
# Usage:
#   ./setup.sh --repo https://github.com/YOURORG/rhoai-deploy-gitops.git
#   ./setup.sh --repo <url> --branch v3.5.0-ea2 --overlay prod --new-overlay
# ─────────────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $0 --repo <git-repo-url> [options]

Configure a cluster overlay for your fork. This updates the single
cluster-config.yaml that drives all ArgoCD applications via Kustomize
replacements.

Required:
  --repo <url>       Your Git repository URL

Options:
  --branch <ref>     Git branch or tag to track (default: main)
  --overlay <name>   Cluster overlay to configure (default: dev)
  --channel <ch>     RHOAI OLM channel: fast|beta|stable (default: beta)
  --dsc <overlay>    DSC overlay: minimal|serving|training|full (default: full)
  --new-overlay      Create a new overlay by copying from dev
  --dry-run          Show what would be changed without modifying files
  --help             Show this help message

Examples:
  # Basic setup — configure for your fork
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git

  # Pin to a specific release tag
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git --branch v3.5.0-ea2

  # Create a production overlay with minimal DSC
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git \\
     --overlay prod --new-overlay --dsc serving --channel fast

  # Preview changes without writing
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git --dry-run
EOF
  exit 0
}

# ─── Defaults ───────────────────────────────────────────────────────────────
REPO_URL=""
BRANCH="main"
OVERLAY="dev"
CHANNEL="beta"
DSC_OVERLAY="full"
NEW_OVERLAY=false
DRY_RUN=false

# ─── Parse arguments ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)        REPO_URL="$2"; shift 2 ;;
    --branch)      BRANCH="$2"; shift 2 ;;
    --overlay)     OVERLAY="$2"; shift 2 ;;
    --channel)     CHANNEL="$2"; shift 2 ;;
    --dsc)         DSC_OVERLAY="$2"; shift 2 ;;
    --new-overlay) NEW_OVERLAY=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --help)        usage ;;
    *)             echo "Error: Unknown option: $1"; echo; usage ;;
  esac
done

if [[ -z "$REPO_URL" ]]; then
  echo "Error: --repo is required"
  echo ""
  usage
fi

# ─── Validate inputs ───────────────────────────────────────────────────────
if [[ "$CHANNEL" != "fast" && "$CHANNEL" != "beta" && "$CHANNEL" != "stable" ]]; then
  echo "Error: --channel must be one of: fast, beta, stable"
  exit 1
fi

valid_overlays=("minimal" "serving" "training" "full" "dev")
if [[ ! " ${valid_overlays[*]} " =~ " ${DSC_OVERLAY} " ]]; then
  echo "Error: --dsc must be one of: ${valid_overlays[*]}"
  exit 1
fi

# ─── Locate files ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/clusters/overlays/$OVERLAY"
CONFIG_FILE="$OVERLAY_DIR/cluster-config.yaml"

# ─── Create new overlay if requested ───────────────────────────────────────
if $NEW_OVERLAY && [[ ! -d "$OVERLAY_DIR" ]]; then
  SOURCE_DIR="$SCRIPT_DIR/clusters/overlays/dev"
  if $DRY_RUN; then
    echo "[dry-run] Would create new overlay: clusters/overlays/$OVERLAY/"
  else
    echo "Creating new overlay '$OVERLAY' from dev..."
    cp -r "$SOURCE_DIR" "$OVERLAY_DIR"
    echo "  Created: clusters/overlays/$OVERLAY/"
  fi
fi

if [[ ! -d "$OVERLAY_DIR" ]]; then
  echo "Error: Overlay directory not found: clusters/overlays/$OVERLAY/"
  echo "  Run with --new-overlay to create it."
  exit 1
fi

# ─── Display configuration ─────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  Configuring: clusters/overlays/$OVERLAY/"
echo "├─────────────────────────────────────────────────────────────┤"
echo "│  Repository:    $REPO_URL"
echo "│  Revision:      $BRANCH"
echo "│  RHOAI Channel: $CHANNEL"
echo "│  DSC Overlay:   $DSC_OVERLAY"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""

if $DRY_RUN; then
  echo "[dry-run] Would write: clusters/overlays/$OVERLAY/cluster-config.yaml"
  echo "[dry-run] No files were modified."
  exit 0
fi

# ─── Write cluster-config.yaml ─────────────────────────────────────────────
cat > "$CONFIG_FILE" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-gitops-config
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/compare-options: IgnoreExtraneous
data:
  # ──────────────────────────────────────────────────────────────────────────────
  # CLUSTER CONFIGURATION
  # ──────────────────────────────────────────────────────────────────────────────
  # Generated by: ./setup.sh --repo $REPO_URL --branch $BRANCH
  # Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # ──────────────────────────────────────────────────────────────────────────────

  repoURL: "$REPO_URL"
  targetRevision: "$BRANCH"
  rhoaiChannel: "$CHANNEL"
  rhoaiOverlay: "$DSC_OVERLAY"
EOF

# ─── Update RHOAI operator channel if patch file exists ────────────────────
CHANNEL_PATCH="$SCRIPT_DIR/components/operators/rhoai-operator/patch-channel.yaml"
if [[ -f "$CHANNEL_PATCH" ]]; then
  cat > "$CHANNEL_PATCH" <<EOF
- op: replace
  path: /spec/channel
  value: $CHANNEL
EOF
  echo "  Updated: components/operators/rhoai-operator/patch-channel.yaml"
fi

# ─── Update DSC app path if rhoai-dsc-app.yaml uses a specific overlay ─────
DSC_APP="$SCRIPT_DIR/components/argocd/apps/rhoai-dsc-app.yaml"
if [[ -f "$DSC_APP" ]]; then
  sed -i.bak "s|path: components/instances/rhoai-instance/overlays/.*|path: components/instances/rhoai-instance/overlays/$DSC_OVERLAY|" "$DSC_APP"
  rm -f "$DSC_APP.bak"
  echo "  Updated: components/argocd/apps/rhoai-dsc-app.yaml (overlay: $DSC_OVERLAY)"
fi

echo "  Updated: clusters/overlays/$OVERLAY/cluster-config.yaml"
echo ""
echo "Done! Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Commit:         git add -A && git commit -m 'Configure for my cluster'"
echo "  3. Push:           git push origin main"
echo "  4. Bootstrap:      oc apply -k clusters/overlays/$OVERLAY/"
echo ""
