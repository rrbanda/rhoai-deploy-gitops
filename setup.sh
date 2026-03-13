#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="https://github.com/rrbanda/rhoai-deploy-gitops.git"

usage() {
  cat <<EOF
Usage: $0 --repo <git-repo-url>

Configure this repository for your fork/clone by replacing the default
Git repo URL in all ArgoCD ApplicationSets and Applications.

Options:
  --repo <url>   Your Git repository URL (must end with .git)
  --dry-run      Show what would be changed without modifying files
  --help         Show this help message

Example:
  $0 --repo https://github.com/myorg/rhoai-deploy-gitops.git
EOF
  exit 0
}

REPO_URL=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO_URL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help)    usage ;;
    *)         echo "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$REPO_URL" ]]; then
  echo "Error: --repo is required"
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILES=(
  "components/argocd/apps/cluster-models-appset.yaml"
  "components/argocd/apps/cluster-services-appset.yaml"
  "components/argocd/apps/cluster-operators-appset.yaml"
  "components/argocd/apps/cluster-instances-appset.yaml"
  "components/argocd/projects/base/platform-project.yaml"
  "components/argocd/projects/base/usecases-project.yaml"
  "clusters/overlays/dev/bootstrap-app.yaml"
  "clusters/overlays/dev/rhoai-instance-app.yaml"
  "clusters/overlays/dev/training-workloads-app.yaml"
)

echo "Replacing repo URL:"
echo "  From: $DEFAULT_REPO"
echo "  To:   $REPO_URL"
echo ""

changed=0
for f in "${FILES[@]}"; do
  filepath="$SCRIPT_DIR/$f"
  if [[ ! -f "$filepath" ]]; then
    echo "  SKIP (not found): $f"
    continue
  fi
  if grep -q "$DEFAULT_REPO" "$filepath"; then
    if $DRY_RUN; then
      echo "  WOULD UPDATE: $f"
    else
      if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s|$DEFAULT_REPO|$REPO_URL|g" "$filepath"
      else
        sed -i "s|$DEFAULT_REPO|$REPO_URL|g" "$filepath"
      fi
      echo "  UPDATED: $f"
    fi
    changed=$((changed + 1))
  else
    echo "  OK (already set): $f"
  fi
done

echo ""
echo "Done. $changed file(s) updated."
if $DRY_RUN; then
  echo "(dry-run mode -- no files were modified)"
fi
