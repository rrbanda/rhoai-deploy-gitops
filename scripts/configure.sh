#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# configure.sh — Configure this repository for your cluster
# ─────────────────────────────────────────────────────────────────────────────
# After forking this repo, run this script to point all ArgoCD applications
# at your fork. It updates a single ConfigMap that drives everything.
#
# Usage:
#   ./scripts/configure.sh --repo https://github.com/YOURORG/rhoai-deploy-gitops.git
#   ./scripts/configure.sh --repo <url> --branch v3.5.0-ea2 --overlay prod --new-overlay
#   ./scripts/configure.sh enable-model gemma2-9b-fp8
#   ./scripts/configure.sh disable-model gemma2-9b-fp8
#   ./scripts/configure.sh list-models
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Subcommands ─────────────────────────────────────────────────────────────

cmd_enable_model() {
  local model="$1"
  local config="$REPO_ROOT/usecases/models/$model/profiles/tier1-minimal/config.json"
  if [[ ! -f "$config" ]]; then
    echo "Error: Model '$model' not found."
    echo "Available models:"
    cmd_list_models
    exit 1
  fi
  if command -v jq &>/dev/null; then
    jq '.enabled = "true"' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
  else
    sed -i.bak 's/"enabled": "false"/"enabled": "true"/' "$config" && rm -f "${config}.bak"
  fi
  echo "✓ Enabled model: $model"
  echo "  Commit and push to deploy via GitOps."
}

cmd_disable_model() {
  local model="$1"
  local config="$REPO_ROOT/usecases/models/$model/profiles/tier1-minimal/config.json"
  if [[ ! -f "$config" ]]; then
    echo "Error: Model '$model' not found."
    exit 1
  fi
  if command -v jq &>/dev/null; then
    jq '.enabled = "false"' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
  else
    sed -i.bak 's/"enabled": "true"/"enabled": "false"/' "$config" && rm -f "${config}.bak"
  fi
  echo "✓ Disabled model: $model"
  echo "  Commit and push to remove via GitOps (prune: true)."
}

cmd_enable_service() {
  local service="$1"
  local config="$REPO_ROOT/usecases/services/$service/profiles/tier1-minimal/config.json"
  if [[ ! -f "$config" ]]; then
    echo "Error: Service '$service' not found."
    echo "Available services:"
    cmd_list_services
    exit 1
  fi
  if command -v jq &>/dev/null; then
    jq '.enabled = "true"' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
  else
    sed -i.bak 's/"enabled": "false"/"enabled": "true"/' "$config" && rm -f "${config}.bak"
  fi
  echo "✓ Enabled service: $service"
  # Check if the service requires customization
  local needs_custom
  needs_custom=$(jq -r '.requires_customization // "false"' "$config" 2>/dev/null || echo "false")
  if [[ "$needs_custom" == "true" ]]; then
    local note
    note=$(jq -r '.customization_note // ""' "$config" 2>/dev/null || echo "")
    echo ""
    echo "  ⚠ This service requires cluster-specific configuration:"
    echo "    $note"
  fi
  echo "  Commit and push to deploy via GitOps."
}

cmd_disable_service() {
  local service="$1"
  local config="$REPO_ROOT/usecases/services/$service/profiles/tier1-minimal/config.json"
  if [[ ! -f "$config" ]]; then
    echo "Error: Service '$service' not found."
    exit 1
  fi
  if command -v jq &>/dev/null; then
    jq '.enabled = "false"' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
  else
    sed -i.bak 's/"enabled": "true"/"enabled": "false"/' "$config" && rm -f "${config}.bak"
  fi
  echo "✓ Disabled service: $service"
  echo "  Commit and push to remove via GitOps (prune: true)."
}

cmd_list_models() {
  echo ""
  echo "Available Models:"
  echo "─────────────────────────────────────────────────────────────"
  printf "  %-25s %-10s %s\n" "NAME" "STATUS" "DESCRIPTION"
  echo "  ─────────────────────────────────────────────────────────"
  for config in "$REPO_ROOT"/usecases/models/*/profiles/tier1-minimal/config.json; do
    if [[ -f "$config" ]]; then
      local name desc enabled
      name=$(jq -r '.name' "$config" 2>/dev/null || basename "$(dirname "$(dirname "$(dirname "$config")")")")
      desc=$(jq -r '.description // "-"' "$config" 2>/dev/null || echo "-")
      enabled=$(jq -r '.enabled' "$config" 2>/dev/null || echo "false")
      local status="disabled"
      [[ "$enabled" == "true" ]] && status="ENABLED"
      printf "  %-25s %-10s %s\n" "$name" "$status" "$desc"
    fi
  done
  echo ""
}

cmd_list_services() {
  echo ""
  echo "Available Services:"
  echo "─────────────────────────────────────────────────────────────"
  printf "  %-25s %-10s %s\n" "NAME" "STATUS" "DESCRIPTION"
  echo "  ─────────────────────────────────────────────────────────"
  for config in "$REPO_ROOT"/usecases/services/*/profiles/tier1-minimal/config.json; do
    if [[ -f "$config" ]]; then
      local name desc enabled
      name=$(jq -r '.name' "$config" 2>/dev/null || basename "$(dirname "$(dirname "$(dirname "$config")")")")
      desc=$(jq -r '.description // "-"' "$config" 2>/dev/null || echo "-")
      enabled=$(jq -r '.enabled' "$config" 2>/dev/null || echo "false")
      local status="disabled"
      [[ "$enabled" == "true" ]] && status="ENABLED"
      printf "  %-25s %-10s %s\n" "$name" "$status" "$desc"
    fi
  done
  echo ""
}

cmd_status() {
  echo ""
  echo "┌─────────────────────────────────────────────────────────────┐"
  echo "│  RHOAI GitOps Deployment Status                             │"
  echo "└─────────────────────────────────────────────────────────────┘"
  cmd_list_models
  cmd_list_services
}

# ─── Check for subcommands ────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
  case "$1" in
    enable-model)
      [[ $# -lt 2 ]] && { echo "Usage: $0 enable-model <name>"; exit 1; }
      cmd_enable_model "$2"; exit 0 ;;
    disable-model)
      [[ $# -lt 2 ]] && { echo "Usage: $0 disable-model <name>"; exit 1; }
      cmd_disable_model "$2"; exit 0 ;;
    enable-service)
      [[ $# -lt 2 ]] && { echo "Usage: $0 enable-service <name>"; exit 1; }
      cmd_enable_service "$2"; exit 0 ;;
    disable-service)
      [[ $# -lt 2 ]] && { echo "Usage: $0 disable-service <name>"; exit 1; }
      cmd_disable_service "$2"; exit 0 ;;
    list-models)   cmd_list_models; exit 0 ;;
    list-services) cmd_list_services; exit 0 ;;
    list|status)   cmd_status; exit 0 ;;
  esac
fi

# ─── Main setup flow ─────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $0 --repo <git-repo-url> [options]
       $0 <subcommand> [args]

Configure a cluster overlay for your fork. This updates the single
cluster-config.yaml that drives all ArgoCD applications via Kustomize
replacements.

Subcommands:
  enable-model <name>     Enable a model for GitOps deployment
  disable-model <name>    Disable a model (removes via prune)
  enable-service <name>   Enable a service for GitOps deployment
  disable-service <name>  Disable a service (removes via prune)
  list-models             Show all available models and their status
  list-services           Show all available services and their status
  status                  Show overall deployment status

Setup options:
  --repo <url>       Your Git repository URL (required for initial setup)
  --branch <ref>     Git branch or tag to track (default: main)
  --overlay <name>   Bootstrap overlay to configure (default: default)
  --channel <ch>     RHOAI OLM channel: fast|beta|stable (default: beta)
  --dsc <overlay>    DSC overlay: minimal|serving|training|full (default: full)
  --new-overlay      Create a new overlay by copying from dev
  --dry-run          Show what would be changed without modifying files
  --help             Show this help message

Examples:
  # Initial setup — configure for your fork
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git

  # Pin to a specific release tag
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git --branch v3.5.0-ea2

  # Create a production overlay with minimal DSC
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git \\
     --overlay prod --new-overlay --dsc serving --channel fast

  # Enable a model for deployment
  $0 enable-model gemma2-9b-fp8

  # Check what's enabled
  $0 status
EOF
  exit 0
}

# ─── Defaults ───────────────────────────────────────────────────────────────
REPO_URL=""
BRANCH="main"
OVERLAY="default"
CHANNEL="fast"
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
OVERLAY_DIR="$REPO_ROOT/bootstrap/overlays/$OVERLAY"
CONFIG_FILE="$OVERLAY_DIR/cluster-config.yaml"

# ─── Create new overlay if requested ───────────────────────────────────────
if $NEW_OVERLAY && [[ ! -d "$OVERLAY_DIR" ]]; then
  SOURCE_DIR="$REPO_ROOT/bootstrap/overlays/default"
  if $DRY_RUN; then
    echo "[dry-run] Would create new overlay: bootstrap/overlays/$OVERLAY/"
  else
    echo "Creating new overlay '$OVERLAY' from default..."
    cp -r "$SOURCE_DIR" "$OVERLAY_DIR"
    echo "  Created: bootstrap/overlays/$OVERLAY/"
  fi
fi

if [[ ! -d "$OVERLAY_DIR" ]]; then
  echo "Error: Overlay directory not found: bootstrap/overlays/$OVERLAY/"
  echo "  Run with --new-overlay to create it."
  exit 1
fi

# ─── Display configuration ─────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  Configuring: bootstrap/overlays/$OVERLAY/"
echo "├─────────────────────────────────────────────────────────────┤"
echo "│  Repository:    $REPO_URL"
echo "│  Revision:      $BRANCH"
echo "│  RHOAI Channel: $CHANNEL"
echo "│  DSC Overlay:   $DSC_OVERLAY"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""

if $DRY_RUN; then
  echo "[dry-run] Would write: bootstrap/overlays/$OVERLAY/cluster-config.yaml"
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
  # Generated by: ./scripts/configure.sh --repo $REPO_URL --branch $BRANCH
  # Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # ──────────────────────────────────────────────────────────────────────────────

  repoURL: "$REPO_URL"
  targetRevision: "$BRANCH"
  rhoaiChannel: "$CHANNEL"
  rhoaiOverlay: "$DSC_OVERLAY"
EOF

# ─── Update RHOAI operator channel if patch file exists ────────────────────
CHANNEL_PATCH="$REPO_ROOT/components/operators/rhoai-operator/patch-channel.yaml"
if [[ -f "$CHANNEL_PATCH" ]]; then
  cat > "$CHANNEL_PATCH" <<EOF
- op: replace
  path: /spec/channel
  value: $CHANNEL
EOF
  echo "  Updated: components/operators/rhoai-operator/patch-channel.yaml"
fi

# ─── Update DSC app path if rhoai-dsc-app.yaml uses a specific overlay ─────
DSC_APP="$REPO_ROOT/components/argocd/apps/rhoai-dsc-app.yaml"
if [[ -f "$DSC_APP" ]]; then
  sed -i.bak "s|path: components/instances/rhoai-instance/overlays/.*|path: components/instances/rhoai-instance/overlays/$DSC_OVERLAY|" "$DSC_APP"
  rm -f "$DSC_APP.bak"
  echo "  Updated: components/argocd/apps/rhoai-dsc-app.yaml (overlay: $DSC_OVERLAY)"
fi

echo "  Updated: bootstrap/overlays/$OVERLAY/cluster-config.yaml"
echo ""
echo "Done! Next steps:"
echo "  1. Review changes:  git diff"
echo "  2. Enable models:   ./scripts/configure.sh enable-model gemma2-9b-fp8"
echo "  3. Enable services: ./scripts/configure.sh enable-service llm-d-epp"
echo "  4. Commit:          git add -A && git commit -m 'Configure for my cluster'"
echo "  5. Push:            git push origin main"
echo "  6. Bootstrap:       until oc apply -k bootstrap/overlays/$OVERLAY; do sleep 10; done"
echo ""
echo "Tip: Run './scripts/configure.sh status' to see what models and services are enabled."
echo ""
