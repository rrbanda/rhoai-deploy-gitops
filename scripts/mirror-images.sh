#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# mirror-images.sh — Discover and mirror container images for disconnected
#                     RHOAI GitOps deployments
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   ./scripts/mirror-images.sh list                          # List all images
#   ./scripts/mirror-images.sh mirror --target-registry <r>  # Mirror images
#   ./scripts/mirror-images.sh generate-imageset             # Generate oc-mirror config
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Defaults ────────────────────────────────────────────────────────────────
TARGET_REGISTRY=""
SOURCE_AUTH=""
TARGET_AUTH=""
DRY_RUN=false
OCP_VERSION="v4.20"
RHOAI_CHANNEL="fast"
RHOAI_VERSION=""

# ─── Image Discovery ────────────────────────────────────────────────────────

discover_images() {
  # Scan all YAML files for image: references, excluding comments and templates
  grep -rh 'image:' --include='*.yaml' --include='*.yml' \
    "$REPO_ROOT/components/" \
    "$REPO_ROOT/usecases/" \
    2>/dev/null \
    | grep -v '^\s*#' \
    | grep -v '{' \
    | sed -E 's/.*image:\s*//' \
    | sed -E 's/["'"'"']//g' \
    | sed 's/^[[:space:]]*//' \
    | sed 's/[[:space:]]*$//' \
    | grep -v '^$' \
    | sort -u
}

# ─── Rewrite image path for target registry ──────────────────────────────────

rewrite_image() {
  local image="$1"
  local target="$2"

  # Strip the source registry prefix and rebuild with target
  local path
  case "$image" in
    registry.redhat.io/*)
      path="${image#registry.redhat.io/}" ;;
    registry.access.redhat.com/*)
      path="${image#registry.access.redhat.com/}" ;;
    quay.io/*)
      path="${image#quay.io/}" ;;
    docker.io/*)
      path="${image#docker.io/}" ;;
    nvcr.io/*)
      path="${image#nvcr.io/}" ;;
    us-central1-docker.pkg.dev/*)
      path="${image#us-central1-docker.pkg.dev/}" ;;
    *)
      path="$image" ;;
  esac

  echo "${target}/${path}"
}

# ─── Subcommand: list ────────────────────────────────────────────────────────

cmd_list() {
  echo ""
  echo "Container Images in Repository"
  echo "══════════════════════════════════════════════════════════════════════"
  echo ""

  local images
  images=$(discover_images)
  local count=0

  local current_registry=""
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue

    local registry
    registry=$(echo "$image" | cut -d'/' -f1)
    if [[ "$registry" != "$current_registry" ]]; then
      [[ -n "$current_registry" ]] && echo ""
      echo "  ── $registry ──"
      current_registry="$registry"
    fi

    echo "    $image"
    count=$((count + 1))
  done <<< "$images"

  echo ""
  echo "──────────────────────────────────────────────────────────────────────"
  echo "  Total: $count unique images"
  echo ""

  if [[ -n "$TARGET_REGISTRY" ]]; then
    echo "Mirror targets (--target-registry $TARGET_REGISTRY):"
    echo ""
    while IFS= read -r image; do
      [[ -z "$image" ]] && continue
      local target
      target=$(rewrite_image "$image" "$TARGET_REGISTRY")
      echo "  $image"
      echo "    → $target"
    done <<< "$images"
    echo ""
  fi
}

# ─── Subcommand: mirror ─────────────────────────────────────────────────────

cmd_mirror() {
  if [[ -z "$TARGET_REGISTRY" ]]; then
    echo "Error: --target-registry is required for mirroring"
    echo "  Example: ./scripts/mirror-images.sh mirror --target-registry myregistry.example.com:5000"
    exit 1
  fi

  local images
  images=$(discover_images)

  echo ""
  echo "Mirroring images to: $TARGET_REGISTRY"
  echo "══════════════════════════════════════════════════════════════════════"
  echo ""

  local src_auth_flag=""
  local tgt_auth_flag=""
  [[ -n "$SOURCE_AUTH" ]] && src_auth_flag="--src-authfile=$SOURCE_AUTH"
  [[ -n "$TARGET_AUTH" ]] && tgt_auth_flag="--dest-authfile=$TARGET_AUTH"

  local total=0 success=0 failed=0

  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    total=$((total + 1))

    local target
    target=$(rewrite_image "$image" "$TARGET_REGISTRY")

    echo "[$total] $image"
    echo "     → $target"

    if $DRY_RUN; then
      echo "     [dry-run] skopeo copy docker://$image docker://$target"
      success=$((success + 1))
    else
      # shellcheck disable=SC2086
      if skopeo copy \
        $src_auth_flag $tgt_auth_flag \
        --all \
        "docker://$image" "docker://$target" 2>&1; then
        echo "     ✓ Success"
        success=$((success + 1))
      else
        echo "     ✗ Failed (continuing)"
        failed=$((failed + 1))
      fi
    fi
    echo ""
  done <<< "$images"

  echo "──────────────────────────────────────────────────────────────────────"
  echo "  Total: $total | Success: $success | Failed: $failed"
  if $DRY_RUN; then
    echo "  (dry-run mode — no images were copied)"
  fi
  echo ""
}

# ─── Subcommand: generate-imageset ──────────────────────────────────────────

cmd_generate_imageset() {
  echo ""
  echo "# ─────────────────────────────────────────────────────────────────"
  echo "# ImageSetConfiguration for oc-mirror"
  echo "# ─────────────────────────────────────────────────────────────────"
  echo "# Generated by: ./scripts/mirror-images.sh generate-imageset"
  echo "# Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "#"
  echo "# This configuration mirrors:"
  echo "#   1. The RHOAI operator from the Red Hat operator index"
  echo "#   2. All workload images used by this GitOps repository"
  echo "#"
  echo "# IMPORTANT: Merge the additionalImages from the official"
  echo "# rhoai-disconnected-install-helper for your RHOAI version:"
  echo "#   https://github.com/red-hat-data-services/rhoai-disconnected-install-helper"
  echo "# ─────────────────────────────────────────────────────────────────"

  cat <<EOF
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:${OCP_VERSION}
      packages:
        - name: rhods-operator
          channels:
            - name: ${RHOAI_CHANNEL}
EOF

  if [[ -n "$RHOAI_VERSION" ]]; then
    echo "              minVersion: ${RHOAI_VERSION}"
    echo "              maxVersion: ${RHOAI_VERSION}"
  fi

  echo "  additionalImages:"

  # Repo-specific workload images
  echo "    # ── Workload images from this GitOps repository ──"
  local images
  images=$(discover_images)
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    echo "    - name: $image"
  done <<< "$images"

  echo ""
  echo "    # ── RHOAI platform images (merge from disconnected helper) ──"
  echo "    # Copy additionalImages from the version-specific markdown at:"
  echo "    #   https://github.com/red-hat-data-services/rhoai-disconnected-install-helper"
  echo "    # Example: rhoai-3.5.md → additionalImages section"
  echo "    # - name: registry.redhat.io/rhoai/odh-workbench-jupyter-minimal-cpu-py312-rhel9@sha256:..."
  echo "    # - name: quay.io/modh/ray@sha256:..."
  echo ""
}

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
  cat <<USAGE
Usage: $0 <command> [options]

Discover and mirror container images for disconnected RHOAI GitOps deployments.

Commands:
  list               List all container images referenced in this repository
  mirror             Mirror images from source registries to a target registry
  generate-imageset  Generate an oc-mirror ImageSetConfiguration

Options:
  --target-registry <url>  Target registry for mirroring (e.g., myregistry.example.com:5000)
  --source-auth <path>     Path to source registry auth file (for skopeo)
  --target-auth <path>     Path to target registry auth file (for skopeo)
  --ocp-version <ver>      OpenShift version for operator index (default: v4.20)
  --channel <ch>           RHOAI OLM channel: fast|beta|stable (default: fast)
  --version <ver>          RHOAI version to pin (e.g., 3.5.0)
  --dry-run                Show what would be done without executing
  --help                   Show this help message

Examples:
  # List all images in the repo
  $0 list

  # List images with mirror targets
  $0 list --target-registry myregistry.example.com:5000

  # Mirror all images (dry-run)
  $0 mirror --target-registry myregistry.example.com:5000 --dry-run

  # Mirror with authentication
  $0 mirror --target-registry myregistry.example.com:5000 \\
    --source-auth ~/.docker/config.json \\
    --target-auth /run/user/1000/containers/auth.json

  # Generate oc-mirror config
  $0 generate-imageset --target-registry myregistry.example.com:5000 \\
    --channel fast --version 3.5.0

Workflow for disconnected deployment:
  1. Run '$0 list' to review images
  2. Run '$0 generate-imageset > imageset-config.yaml'
  3. Merge RHOAI platform images from rhoai-disconnected-install-helper
  4. Run 'oc mirror --config=imageset-config.yaml ...'
  5. Apply IDMS/CatalogSource from oc-mirror output to the cluster
  6. Run './scripts/configure.sh --registry myregistry.example.com:5000 ...'
  7. Bootstrap: 'until oc apply -k bootstrap/overlays/disconnected; do sleep 10; done'
USAGE
  exit 0
}

# ─── Parse arguments ─────────────────────────────────────────────────────────

COMMAND=""

if [[ $# -eq 0 ]]; then
  usage
fi

COMMAND="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-registry) TARGET_REGISTRY="$2"; shift 2 ;;
    --source-auth)     SOURCE_AUTH="$2"; shift 2 ;;
    --target-auth)     TARGET_AUTH="$2"; shift 2 ;;
    --ocp-version)     OCP_VERSION="$2"; shift 2 ;;
    --channel)         RHOAI_CHANNEL="$2"; shift 2 ;;
    --version)         RHOAI_VERSION="$2"; shift 2 ;;
    --dry-run)         DRY_RUN=true; shift ;;
    --help)            usage ;;
    *)                 echo "Error: Unknown option: $1"; echo; usage ;;
  esac
done

# ─── Dispatch ────────────────────────────────────────────────────────────────

case "$COMMAND" in
  list)             cmd_list ;;
  mirror)           cmd_mirror ;;
  generate-imageset) cmd_generate_imageset ;;
  --help|-h|help)   usage ;;
  *)                echo "Error: Unknown command: $COMMAND"; echo; usage ;;
esac
