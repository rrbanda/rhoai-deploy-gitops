#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --repo <git-repo-url> [--branch <branch>] [--overlay <name>]

Configure a cluster overlay for your fork by updating the single
cluster-config.yaml that drives all ArgoCD manifests via Kustomize replacements.

Options:
  --repo <url>       Your Git repository URL (required)
  --branch <branch>  Git branch to track (default: main)
  --overlay <name>   Cluster overlay to configure (default: dev)
  --new-overlay      Create a new overlay by copying from dev
  --dry-run          Show what would be changed without modifying files
  --help             Show this help message

Examples:
  # Configure existing dev overlay for your fork
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git

  # Configure with a specific branch
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git --branch release/v1

  # Create and configure a new prod overlay
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git --overlay prod --new-overlay
EOF
  exit 0
}

REPO_URL=""
BRANCH="main"
OVERLAY="dev"
NEW_OVERLAY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)        REPO_URL="$2"; shift 2 ;;
    --branch)      BRANCH="$2"; shift 2 ;;
    --overlay)     OVERLAY="$2"; shift 2 ;;
    --new-overlay) NEW_OVERLAY=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --help)        usage ;;
    *)             echo "Error: Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$REPO_URL" ]]; then
  echo "Error: --repo is required"
  echo ""
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/clusters/overlays/$OVERLAY"
CONFIG_FILE="$OVERLAY_DIR/cluster-config.yaml"

if $NEW_OVERLAY && [[ ! -d "$OVERLAY_DIR" ]]; then
  SOURCE_DIR="$SCRIPT_DIR/clusters/overlays/dev"
  if $DRY_RUN; then
    echo "[dry-run] Would create new overlay: $OVERLAY_DIR (copied from dev)"
  else
    echo "Creating new overlay '$OVERLAY' from dev..."
    cp -r "$SOURCE_DIR" "$OVERLAY_DIR"
    echo "  Created: clusters/overlays/$OVERLAY/"
  fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  echo "  Run with --new-overlay to create the overlay first."
  exit 1
fi

echo "Configuring cluster overlay: clusters/overlays/$OVERLAY/"
echo "  Repository: $REPO_URL"
echo "  Branch:     $BRANCH"
echo ""

if $DRY_RUN; then
  echo "[dry-run] Would update: clusters/overlays/$OVERLAY/cluster-config.yaml"
  echo ""
  echo "  repoURL: \"$REPO_URL\""
  echo "  targetRevision: \"$BRANCH\""
  echo "  rhoaiOverlay: \"$OVERLAY\""
  echo ""
  echo "(dry-run mode -- no files were modified)"
  exit 0
fi

cat > "$CONFIG_FILE" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-gitops-config
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/compare-options: IgnoreExtraneous
data:
  repoURL: "$REPO_URL"
  targetRevision: "$BRANCH"
  rhoaiOverlay: "$OVERLAY"
EOF

echo "  Updated: clusters/overlays/$OVERLAY/cluster-config.yaml"
echo ""
echo "Done. Validate with:"
echo "  kubectl kustomize clusters/overlays/$OVERLAY/"
