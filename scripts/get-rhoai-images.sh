#!/usr/bin/env bash
# =============================================================================
# get-rhoai-images.sh — Discover all container images used by Red Hat OpenShift AI
#
# Extracts images from:
#   1. Running pods in RHOAI-managed namespaces
#   2. RHOAI operator CSV (relatedImages — the full operator image manifest)
#   3. ImageStreams (notebook and serving runtime images)
#   4. ServingRuntime / ClusterServingRuntime templates
#   5. InferenceService pods across all namespaces
#
# Usage:
#   ./scripts/get-rhoai-images.sh              # all sources, deduplicated
#   ./scripts/get-rhoai-images.sh --pods        # only running pod images
#   ./scripts/get-rhoai-images.sh --csv         # only operator CSV relatedImages
#   ./scripts/get-rhoai-images.sh --imagestreams # only ImageStream images
#   ./scripts/get-rhoai-images.sh --serving     # only ServingRuntime images
#   ./scripts/get-rhoai-images.sh --inference   # only InferenceService pod images
#   ./scripts/get-rhoai-images.sh --output FILE # write results to file
#   ./scripts/get-rhoai-images.sh --json        # output as JSON array
#   ./scripts/get-rhoai-images.sh --by-namespace # group images by namespace
#
# Prerequisites:
#   - oc CLI logged in with cluster-admin or read access to RHOAI namespaces
# =============================================================================
set -euo pipefail

# ---------- Configuration ----------
RHOAI_NAMESPACES=(
  "redhat-ods-operator"
  "redhat-ods-applications"
  "redhat-ods-monitoring"
  "istio-system"
  "knative-serving"
  "redhat-ods-applications-auth-provider"
)

OPERATOR_NS="redhat-ods-operator"
APPS_NS="redhat-ods-applications"

# ---------- CLI flags ----------
MODE="all"
OUTPUT_FILE=""
JSON_OUTPUT=false
BY_NAMESPACE=false

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --pods          Only show images from running pods"
  echo "  --csv           Only show images from operator CSV relatedImages"
  echo "  --imagestreams  Only show images from ImageStreams"
  echo "  --serving       Only show images from ServingRuntime templates"
  echo "  --inference     Only show images from InferenceService pods"
  echo "  --by-namespace  Group images by source namespace"
  echo "  --json          Output as JSON array"
  echo "  --output FILE   Write results to FILE"
  echo "  -h, --help      Show this help"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pods)         MODE="pods"; shift ;;
    --csv)          MODE="csv"; shift ;;
    --imagestreams) MODE="imagestreams"; shift ;;
    --serving)      MODE="serving"; shift ;;
    --inference)    MODE="inference"; shift ;;
    --by-namespace) BY_NAMESPACE=true; shift ;;
    --json)         JSON_OUTPUT=true; shift ;;
    --output)       OUTPUT_FILE="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
  esac
done

# ---------- Helpers ----------
log() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }

check_oc() {
  if ! command -v oc &>/dev/null; then
    echo "ERROR: 'oc' CLI not found. Install it and log in to your cluster." >&2
    exit 1
  fi
  if ! oc whoami &>/dev/null; then
    echo "ERROR: Not logged in to an OpenShift cluster. Run 'oc login' first." >&2
    exit 1
  fi
  log "Logged in as: $(oc whoami) on $(oc whoami --show-server)"
}

namespace_exists() {
  oc get namespace "$1" &>/dev/null 2>&1
}

# ---------- Image extraction functions ----------

get_pod_images() {
  local ns="$1"
  if ! namespace_exists "$ns"; then
    warn "Namespace '$ns' does not exist, skipping"
    return
  fi

  oc get pods -n "$ns" -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null || true
}

get_all_pod_images() {
  log "Collecting images from running pods..."
  local all_images=""

  for ns in "${RHOAI_NAMESPACES[@]}"; do
    local images
    images=$(get_pod_images "$ns")
    if [[ -n "$images" ]]; then
      if $BY_NAMESPACE; then
        echo "# --- Namespace: $ns ---"
        echo "$images" | sort -u
        echo ""
      fi
      all_images+="${images}"$'\n'
    fi
  done

  if ! $BY_NAMESPACE; then
    echo "$all_images"
  fi
}

get_csv_related_images() {
  log "Collecting images from RHOAI operator CSV (relatedImages)..."

  if ! namespace_exists "$OPERATOR_NS"; then
    warn "Operator namespace '$OPERATOR_NS' does not exist"
    return
  fi

  local csv_name
  csv_name=$(oc get csv -n "$OPERATOR_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | grep -i "rhods\|opendatahub\|rhoai" | head -1 || true)

  if [[ -z "$csv_name" ]]; then
    warn "No RHOAI CSV found in $OPERATOR_NS. Trying all CSVs..."
    csv_name=$(oc get csv -n "$OPERATOR_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
      | head -1 || true)
  fi

  if [[ -z "$csv_name" ]]; then
    warn "No CSV found in $OPERATOR_NS"
    return
  fi

  log "Found CSV: $csv_name"

  if $BY_NAMESPACE; then
    echo "# --- Source: CSV relatedImages ($csv_name) ---"
  fi

  oc get csv "$csv_name" -n "$OPERATOR_NS" -o jsonpath='{range .spec.relatedImages[*]}{.image}{"\n"}{end}' 2>/dev/null || true

  oc get csv "$csv_name" -n "$OPERATOR_NS" \
    -o jsonpath='{range .spec.install.spec.deployments[*]}{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}{range .spec.template.spec.initContainers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null || true

  if $BY_NAMESPACE; then
    echo ""
  fi
}

get_imagestream_images() {
  log "Collecting images from ImageStreams..."

  if ! namespace_exists "$APPS_NS"; then
    warn "Applications namespace '$APPS_NS' does not exist"
    return
  fi

  if $BY_NAMESPACE; then
    echo "# --- Source: ImageStreams ($APPS_NS) ---"
  fi

  # spec.tags[].from.name — the source image references
  oc get imagestreams -n "$APPS_NS" -o jsonpath='{range .items[*]}{range .spec.tags[*]}{.from.name}{"\n"}{end}{end}' 2>/dev/null \
    | grep -v "^$" || true

  # status.tags[].items[].dockerImageReference — resolved digests
  oc get imagestreams -n "$APPS_NS" -o jsonpath='{range .items[*]}{range .status.tags[*]}{range .items[*]}{.dockerImageReference}{"\n"}{end}{end}{end}' 2>/dev/null \
    | grep -v "^$" || true

  if $BY_NAMESPACE; then
    echo ""
  fi
}

get_serving_runtime_images() {
  log "Collecting images from ServingRuntime and ClusterServingRuntime..."

  if $BY_NAMESPACE; then
    echo "# --- Source: ServingRuntime / ClusterServingRuntime ---"
  fi

  oc get clusterservingruntimes -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null || true

  if namespace_exists "$APPS_NS"; then
    oc get servingruntimes -n "$APPS_NS" -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null || true
  fi

  oc get templates -n "$APPS_NS" -o jsonpath='{range .items[*]}{range .objects[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}{end}' 2>/dev/null || true

  if $BY_NAMESPACE; then
    echo ""
  fi
}

get_inference_pod_images() {
  log "Collecting images from InferenceService pods (all namespaces)..."

  if $BY_NAMESPACE; then
    echo "# --- Source: InferenceService pods ---"
  fi

  local isvc_namespaces
  isvc_namespaces=$(oc get inferenceservices --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u || true)

  if [[ -z "$isvc_namespaces" ]]; then
    warn "No InferenceServices found on cluster"
    return
  fi

  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    local images
    images=$(oc get pods -n "$ns" -l 'serving.kserve.io/inferenceservice' \
      -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null || true)
    if [[ -n "$images" ]]; then
      if $BY_NAMESPACE; then
        echo "# Namespace: $ns"
      fi
      echo "$images"
    fi
  done <<< "$isvc_namespaces"

  if $BY_NAMESPACE; then
    echo ""
  fi
}

# ---------- Additional sources ----------

get_datasciencecluster_images() {
  log "Collecting images referenced in DataScienceCluster status..."
  oc get datasciencecluster -o jsonpath='{range .items[*]}{range .status.relatedImages[*]}{.}{"\n"}{end}{end}' 2>/dev/null || true
}

get_additional_operator_images() {
  log "Collecting images from related operator CSVs..."

  local csv_list
  csv_list=$(oc get csv -n "openshift-operators" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  local related_csvs=()
  while IFS= read -r csv; do
    [[ -z "$csv" ]] && continue
    case "$csv" in
      *servicemesh*|*serverless*|*authorino*|*gpu*|*nfd*|*cert-manager*|*kueue*)
        related_csvs+=("$csv")
        ;;
    esac
  done <<< "$csv_list"

  local csv
  for csv in "${related_csvs[@]}"; do
    if $BY_NAMESPACE; then
      echo "# --- Related CSV: $csv ---"
    fi
    oc get csv "$csv" -n "openshift-operators" \
      -o jsonpath='{range .spec.relatedImages[*]}{.image}{"\n"}{end}' 2>/dev/null || true
  done
}

# ---------- Output formatting ----------

format_output() {
  local images="$1"

  images=$(echo "$images" | grep -v "^#" | grep -v "^$" | sort -u)

  local count
  count=$(echo "$images" | wc -l | tr -d ' ')

  if $JSON_OUTPUT; then
    echo "["
    local first=true
    while IFS= read -r img; do
      if [[ -z "$img" ]]; then continue; fi
      if $first; then
        first=false
      else
        echo ","
      fi
      printf '  "%s"' "$img"
    done <<< "$images"
    echo ""
    echo "]"
  else
    echo "$images"
  fi

  log "Total unique images found: $count"
}

format_by_namespace() {
  local images="$1"
  if $JSON_OUTPUT; then
    echo "$images" | grep -v "^$" | grep -v "^#"
  else
    echo "$images"
  fi
  local count
  count=$(echo "$images" | grep -v "^#" | grep -v "^$" | sort -u | wc -l | tr -d ' ')
  log "Total unique images found: $count"
}

# ---------- Main ----------

main() {
  check_oc

  log "============================================="
  log "  RHOAI Image Discovery"
  log "  Cluster: $(oc whoami --show-server)"
  log "  Mode: $MODE"
  log "============================================="

  local all_images=""

  case "$MODE" in
    pods)
      all_images=$(get_all_pod_images)
      ;;
    csv)
      all_images=$(get_csv_related_images)
      ;;
    imagestreams)
      all_images=$(get_imagestream_images)
      ;;
    serving)
      all_images=$(get_serving_runtime_images)
      ;;
    inference)
      all_images=$(get_inference_pod_images)
      ;;
    all)
      all_images+=$(get_all_pod_images)$'\n'
      all_images+=$(get_csv_related_images)$'\n'
      all_images+=$(get_imagestream_images)$'\n'
      all_images+=$(get_serving_runtime_images)$'\n'
      all_images+=$(get_inference_pod_images)$'\n'
      all_images+=$(get_datasciencecluster_images)$'\n'
      all_images+=$(get_additional_operator_images)$'\n'
      ;;
  esac

  local output
  if $BY_NAMESPACE; then
    output=$(format_by_namespace "$all_images")
  else
    output=$(format_output "$all_images")
  fi

  if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$output" > "$OUTPUT_FILE"
    log "Results written to: $OUTPUT_FILE"
  else
    echo "$output"
  fi
}

main
