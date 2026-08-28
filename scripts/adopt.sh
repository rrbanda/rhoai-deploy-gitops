#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# adopt.sh — Adopt a manually installed RHOAI into GitOps management
# ─────────────────────────────────────────────────────────────────────────────
# When RHOAI is already installed manually (via OperatorHub, CLI, etc.),
# this script helps transition to GitOps management by discovering the
# current cluster state, identifying mismatches with the Git repo, and
# guiding the alignment process.
#
# Usage:
#   ./scripts/adopt.sh audit              # Discover what's installed
#   ./scripts/adopt.sh export [dir]       # Export current state for Git alignment
#   ./scripts/adopt.sh verify             # Verify GitOps alignment post-adoption
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Helpers ─────────────────────────────────────────────────────────────────

require_oc() {
  if ! command -v oc &>/dev/null; then
    echo "Error: 'oc' CLI not found. Install it and log in." >&2
    exit 1
  fi
  if ! oc whoami &>/dev/null 2>&1; then
    echo "Error: Not logged in. Run 'oc login' first." >&2
    exit 1
  fi
}

require_python3() {
  if ! command -v python3 &>/dev/null; then
    echo "Error: 'python3' not found. It is required for JSON/YAML parsing." >&2
    echo "       Install it or use a container with python3 available." >&2
    exit 1
  fi
}

header() {
  echo ""
  echo "┌─────────────────────────────────────────────────────────────┐"
  echo "│  $1"
  echo "└─────────────────────────────────────────────────────────────┘"
}

# Known RHOAI-related operators: git-dir|subscription-name|namespace
# Uses a plain indexed array for bash 3.2+ (macOS) compatibility.
OPERATOR_ENTRIES=(
  "openshift-ai|rhods-operator|redhat-ods-operator"
  "cert-manager|openshift-cert-manager-operator|cert-manager-operator"
  "node-feature-discovery|nfd|openshift-nfd"
  "gpu|gpu-operator-certified|nvidia-gpu-operator"
  "servicemesh|servicemeshoperator3|openshift-operators"
  "kueue|kueue-operator|openshift-kueue-operator"
  "jobset|job-set|openshift-jobset-operator"
  "leader-worker-set|leader-worker-set|openshift-lws"
  "custom-metrics-autoscaler|openshift-custom-metrics-autoscaler-operator|openshift-custom-metrics-autoscaler"
  "external-secrets|openshift-external-secrets-operator|external-secrets-operator"
  "connectivity-link|rhcl-operator|kuadrant-system"
  "developer-hub|rhdh|rhdh-operator"
)

# ─── Subcommand: audit ───────────────────────────────────────────────────────

cmd_audit() {
  require_oc
  require_python3

  header "Brownfield Audit — Cluster State Discovery"
  echo ""
  echo "  This is a read-only check — no changes are made to the cluster or Git."
  echo ""
  echo "  Cluster: $(oc whoami --show-server 2>/dev/null)"
  echo "  User:    $(oc whoami 2>/dev/null)"
  echo ""

  local total_found=0
  local total_expected=${#OPERATOR_ENTRIES[@]}
  local mismatches=0

  # ── Operator Subscriptions ──

  echo "  ── Operator Subscriptions ──"
  echo ""
  printf "  %-20s %-45s %-25s %-15s %-20s %s\n" \
    "GITOPS DIR" "SUBSCRIPTION" "NAMESPACE" "CHANNEL" "SOURCE" "STATUS"
  echo "  ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────"

  for entry in "${OPERATOR_ENTRIES[@]}"; do
    IFS='|' read -r git_dir expected_sub expected_ns <<< "$entry"
    local status="NOT INSTALLED"
    local ch="" src="" detail=""

    local sub_json
    sub_json="$(oc get sub "$expected_sub" -n "$expected_ns" -o json 2>/dev/null || echo "")"

    if [[ -n "$sub_json" ]]; then
      total_found=$((total_found + 1))
      ch="$(echo "$sub_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('channel','?'))" 2>/dev/null || echo "?")"
      src="$(echo "$sub_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['spec'].get('source','?'))" 2>/dev/null || echo "?")"
      local sub_state
      sub_state="$(echo "$sub_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',{}).get('state','Unknown'))" 2>/dev/null || echo "?")"

      local git_ch="" git_src=""
      local ch_patch="$REPO_ROOT/components/operators/$git_dir/patch-channel.yaml"
      local src_patch="$REPO_ROOT/components/operators/$git_dir/patch-source.yaml"
      [[ -f "$ch_patch" ]] && git_ch="$(grep 'value:' "$ch_patch" 2>/dev/null | head -1 | sed 's/.*value:[[:space:]]*//' | tr -d '"[:space:]' || true)"
      [[ -f "$src_patch" ]] && git_src="$(grep 'value:' "$src_patch" 2>/dev/null | head -1 | sed 's/.*value:[[:space:]]*//' | tr -d '"[:space:]' || true)"

      if [[ -n "$git_ch" && "$ch" != "$git_ch" ]]; then
        status="MISMATCH"
        detail="channel: cluster=$ch git=$git_ch"
        mismatches=$((mismatches + 1))
      elif [[ -n "$git_src" && "$src" != "$git_src" ]]; then
        status="MISMATCH"
        detail="source: cluster=$src git=$git_src"
        mismatches=$((mismatches + 1))
      else
        status="OK ($sub_state)"
      fi
    fi

    printf "  %-20s %-45s %-25s %-15s %-20s %s\n" \
      "$git_dir" "$expected_sub" "$expected_ns" "${ch:-—}" "${src:-—}" "$status"
    if [[ -n "$detail" ]]; then
      echo "        → $detail"
      echo "        Fix: Run ./scripts/adopt.sh export to capture cluster values"
    fi
  done

  # ── Other Subscriptions on Cluster ──
  # Discover subscriptions that exist but weren't matched above. Helps users
  # who installed operators with non-standard names or from different catalogs.

  echo ""
  echo "  ── Other Subscriptions on Cluster ──"
  echo ""

  local known_subs=""
  for entry in "${OPERATOR_ENTRIES[@]}"; do
    IFS='|' read -r _ sub _ <<< "$entry"
    known_subs="$known_subs $sub "
  done

  local other_found=0
  local all_subs
  all_subs="$(oc get sub --all-namespaces --no-headers 2>/dev/null || echo "")"
  if [[ -n "$all_subs" ]]; then
    while IFS= read -r line; do
      local sub_ns sub_name
      sub_ns="$(echo "$line" | awk '{print $1}')"
      sub_name="$(echo "$line" | awk '{print $2}')"
      if [[ "$known_subs" != *" $sub_name "* ]]; then
        echo "  INFO  $sub_name (ns: $sub_ns)"
        other_found=$((other_found + 1))
      fi
    done <<< "$all_subs"
  fi
  if [[ $other_found -eq 0 ]]; then
    echo "  (none — all cluster subscriptions are accounted for)"
  else
    echo ""
    echo "  $other_found subscription(s) not managed by this repo (this is normal for"
    echo "  platform operators like logging, monitoring, pipelines, etc.)"
  fi

  # ── OperatorGroups ──

  echo ""
  echo "  ── OperatorGroup Name Alignment ──"
  echo ""

  local og_mismatches=0
  for entry in "${OPERATOR_ENTRIES[@]}"; do
    IFS='|' read -r git_dir _sub expected_ns <<< "$entry"
    [[ "$expected_ns" == "openshift-operators" ]] && continue

    local cluster_og
    cluster_og="$(oc get operatorgroup -n "$expected_ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
    [[ -z "$cluster_og" ]] && continue

    local git_og=""
    local og_file="$REPO_ROOT/components/operators/$git_dir/operatorgroup.yaml"
    if [[ -f "$og_file" ]]; then
      git_og="$(grep '^[[:space:]]*name:' "$og_file" | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d '"')"
    else
      local kust="$REPO_ROOT/components/operators/$git_dir/kustomization.yaml"
      if [[ -f "$kust" ]]; then
        local vendor_ref
        vendor_ref="$(grep -E '^\s*-\s*\.\./\.\./\.\./' "$kust" | head -1 | sed 's/.*- //')"
        if [[ -n "$vendor_ref" ]]; then
          local vendor_dir
          vendor_dir="$(cd "$REPO_ROOT/components/operators/$git_dir" && cd "$vendor_ref" 2>/dev/null && pwd)"
          for og_name_file in "$vendor_dir/operatorgroup.yaml" "$vendor_dir/operator-group.yaml"; do
            if [[ -f "$og_name_file" ]]; then
              git_og="$(grep '^[[:space:]]*name:' "$og_name_file" | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d '"')"
              [[ -n "$git_og" ]] && break
            fi
          done
        fi
      fi
    fi

    if [[ -n "$git_og" && -n "$cluster_og" ]]; then
      if [[ "$cluster_og" == "$git_og" ]]; then
        echo "  PASS  $expected_ns: OG name matches ($cluster_og)"
      else
        echo "  WARN  $expected_ns: OG name mismatch — cluster='$cluster_og' git='$git_og'"
        echo "        ArgoCD will try to create '$git_og' which may conflict."
        echo "        Fix: Use the OG name override patch (see docs/adoption.md)"
        og_mismatches=$((og_mismatches + 1))
      fi
    fi
  done

  # ── DataScienceCluster ──

  echo ""
  echo "  ── DataScienceCluster ──"
  echo ""

  local dsc_json
  dsc_json="$(oc get datasciencecluster -o json 2>/dev/null || echo '{"items":[]}')"
  local dsc_count
  dsc_count="$(echo "$dsc_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))" 2>/dev/null || echo "0")"

  if [[ "$dsc_count" -eq 0 ]]; then
    echo "  INFO  No DataScienceCluster found — will be created by GitOps"
  else
    echo "$dsc_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for dsc in data.get('items', []):
    name = dsc['metadata']['name']
    ready = 'Unknown'
    for c in dsc.get('status',{}).get('conditions',[]):
        if c['type'] == 'Ready':
            ready = c['status']
    print(f'  Name: {name}')
    print(f'  Ready: {ready}')
    components = dsc.get('spec',{}).get('components',{})
    if components:
        print('  Components:')
        for comp_name, comp_spec in sorted(components.items()):
            state = comp_spec.get('managementState', 'Unknown') if isinstance(comp_spec, dict) else str(comp_spec)
            print(f'    {comp_name}: {state}')
    nim = dsc.get('spec',{}).get('components',{}).get('kserve',{}).get('nim',{})
    if nim:
        print(f'  nim.airGapped: {nim.get(\"airGapped\", False)}')
" 2>/dev/null || echo "  WARN  Could not parse DSC (python3 required)"
  fi

  # ── CatalogSources ──

  echo ""
  echo "  ── CatalogSources ──"
  echo ""

  oc get catalogsource -n openshift-marketplace --no-headers 2>/dev/null | while read -r name _rest; do
    local cs_status cs_image
    cs_status="$(oc get catalogsource "$name" -n openshift-marketplace -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null || echo "?")"
    cs_image="$(oc get catalogsource "$name" -n openshift-marketplace -o jsonpath='{.spec.image}' 2>/dev/null || echo "?")"
    echo "  $name"
    echo "    Status: $cs_status"
    echo "    Image:  ${cs_image:0:80}"
  done

  # ── IDMS/ICSP ──

  echo ""
  echo "  ── Image Mirror Rules ──"
  echo ""

  local idms_count icsp_count
  idms_count="$(oc get imagedigestmirrorset --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  icsp_count="$(oc get imagecontentsourcepolicy --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "  ImageDigestMirrorSets:     $idms_count"
  echo "  ImageContentSourcePolicies: $icsp_count"

  # ── Operators in Git but NOT on Cluster ──

  local not_found_count=$((total_expected - total_found))
  if [[ $not_found_count -gt 0 ]]; then
    echo ""
    echo "  ── WARNING: Operators in Git Not Found on Cluster ──"
    echo ""
    echo "  ArgoCD will INSTALL these operators when you bootstrap:"
    echo ""
    for entry in "${OPERATOR_ENTRIES[@]}"; do
      IFS='|' read -r git_dir expected_sub expected_ns <<< "$entry"
      local check_json
      check_json="$(oc get sub "$expected_sub" -n "$expected_ns" -o name 2>/dev/null || echo "")"
      if [[ -z "$check_json" ]]; then
        echo "    - $git_dir ($expected_sub in $expected_ns)"
      fi
    done
    echo ""
    echo "  If you do NOT want these operators, exclude their directories from"
    echo "  the ApplicationSet before bootstrapping. See docs/adoption.md."
  fi

  # ── Non-OLM components deployed by GitOps ──

  local non_olm_dirs=""
  for op_dir in "$REPO_ROOT"/components/operators/*/; do
    [[ -d "$op_dir" ]] || continue
    local dir_name
    dir_name="$(basename "$op_dir")"
    local kust="$op_dir/kustomization.yaml"
    [[ -f "$kust" ]] || continue
    if ! grep -q 'Subscription' "$kust" 2>/dev/null; then
      non_olm_dirs="$non_olm_dirs $dir_name"
    fi
  done
  if [[ -n "$non_olm_dirs" ]]; then
    echo ""
    echo "  ── Non-OLM Components (deployed via raw manifests) ──"
    echo ""
    echo "  These are not OLM operators but will be deployed by the ApplicationSet:"
    for d in $non_olm_dirs; do
      echo "    - $d"
    done
  fi

  # ── Summary ──

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  AUDIT SUMMARY"
  echo ""
  echo "  Operators on cluster: $total_found / $total_expected managed by this repo"
  echo "  Mismatches:           $mismatches (channel/source differ from Git)"
  echo "  OG conflicts:         $og_mismatches"
  echo "  Will be added:        $not_found_count (ArgoCD will install these after bootstrap)"
  echo ""

  if [[ $not_found_count -gt 0 ]]; then
    echo "  IMPORTANT: ArgoCD will install $not_found_count operator(s) not currently"
    echo "  on this cluster. Review the list above. To prevent this, exclude"
    echo "  unwanted operator directories in the ApplicationSet exclude list."
    echo ""
  fi

  if [[ $mismatches -gt 0 || $og_mismatches -gt 0 ]]; then
    echo "  Next steps:"
    echo "    1. Export current state:  ./scripts/adopt.sh export"
    echo "    2. Align Git to cluster:  Review the exported values and update patches"
    echo "    3. Verify alignment:      ./scripts/adopt.sh verify"
    echo "    4. Bootstrap GitOps:      until oc apply -k bootstrap/overlays/<overlay>; do sleep 10; done"
  elif [[ $not_found_count -gt 0 ]]; then
    echo "  Next steps:"
    echo "    1. Review operator list above — exclude any you don't want"
    echo "    2. Export current state:  ./scripts/adopt.sh export"
    echo "    3. Run the generated configure command"
    echo "    4. Verify alignment:      ./scripts/adopt.sh verify"
    echo "    5. Bootstrap GitOps"
  else
    echo "  Cluster state matches Git repo. Safe to bootstrap GitOps."
    echo "    until oc apply -k bootstrap/overlays/<overlay>; do sleep 10; done"
  fi
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
}

# ─── Subcommand: export ──────────────────────────────────────────────────────

cmd_export() {
  require_oc
  require_python3
  local output_dir="${1:-$REPO_ROOT/adoption-export}"

  header "Export Cluster State for Git Alignment"
  echo ""
  echo "  Exporting to: $output_dir"
  echo ""

  mkdir -p "$output_dir"

  # ── Export operator channels file ──

  local channels_file="$output_dir/operator-channels.conf"
  echo "# Operator channels exported from cluster on $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$channels_file"
  echo "# Use with: ./scripts/configure.sh --operator-channels $channels_file" >> "$channels_file"
  echo "" >> "$channels_file"

  for entry in "${OPERATOR_ENTRIES[@]}"; do
    IFS='|' read -r git_dir expected_sub expected_ns <<< "$entry"
    local ch
    ch="$(oc get sub "$expected_sub" -n "$expected_ns" -o jsonpath='{.spec.channel}' 2>/dev/null || echo "")"
    if [[ -n "$ch" ]]; then
      echo "$git_dir=$ch" >> "$channels_file"
    fi
  done
  echo "  Created: $(basename "$channels_file")"

  # ── Export catalog source names ──

  local catalog_file="$output_dir/catalog-sources.txt"
  echo "# CatalogSources from cluster on $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$catalog_file"
  echo "" >> "$catalog_file"

  local rhoai_src gpu_src
  rhoai_src="$(oc get sub rhods-operator -n redhat-ods-operator -o jsonpath='{.spec.source}' 2>/dev/null || echo "redhat-operators")"
  echo "redhat-operators=$rhoai_src" >> "$catalog_file"

  gpu_src="$(oc get sub gpu-operator-certified -n nvidia-gpu-operator -o jsonpath='{.spec.source}' 2>/dev/null || echo "certified-operators")"
  echo "certified-operators=$gpu_src" >> "$catalog_file"

  echo "  Created: $(basename "$catalog_file")"

  # ── Export DSC spec ──

  local dsc_file="$output_dir/datasciencecluster.yaml"
  oc get datasciencecluster -o yaml 2>/dev/null > "$dsc_file" || echo "# No DSC found" > "$dsc_file"
  echo "  Created: $(basename "$dsc_file")"

  # ── Export OperatorGroup names ──

  local og_file="$output_dir/operatorgroups.txt"
  echo "# OperatorGroup names from cluster on $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$og_file"
  echo "# Format: namespace=operatorgroup-name" >> "$og_file"
  echo "" >> "$og_file"

  for entry in "${OPERATOR_ENTRIES[@]}"; do
    IFS='|' read -r _dir _sub expected_ns <<< "$entry"
    [[ "$expected_ns" == "openshift-operators" ]] && continue
    local og_name
    og_name="$(oc get operatorgroup -n "$expected_ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
    [[ -n "$og_name" ]] && echo "$expected_ns=$og_name" >> "$og_file"
  done
  echo "  Created: $(basename "$og_file")"

  # ── Detect mirror registry from IDMS/ICSP ──
  # Prefer the mirror for registry.redhat.io (most relevant for RHOAI operators),
  # fall back to the first mirror entry if not found.

  local mirror_registry=""
  local all_mirrors
  all_mirrors="$(oc get imagedigestmirrorset -o json 2>/dev/null || echo '{"items":[]}')"
  mirror_registry="$(echo "$all_mirrors" | python3 -c "
import sys, json
data = json.load(sys.stdin)
best = ''
fallback = ''
for item in data.get('items', []):
    for rule in item.get('spec', {}).get('imageDigestMirrors', []):
        source = rule.get('source', '')
        mirrors = rule.get('mirrors', [])
        if not mirrors:
            continue
        if not fallback:
            fallback = mirrors[0]
        if 'registry.redhat.io' in source:
            best = mirrors[0]
            break
    if best:
        break
print(best or fallback)
" 2>/dev/null || echo "")"

  if [[ -z "$mirror_registry" ]]; then
    mirror_registry="$(oc get imagecontentsourcepolicy -o jsonpath='{.items[0].spec.repositoryDigestMirrors[0].mirrors[0]}' 2>/dev/null || echo "")"
  fi
  if [[ -n "$mirror_registry" ]]; then
    mirror_registry="$(echo "$mirror_registry" | sed 's|/.*||')"
    echo "  Detected mirror registry: $mirror_registry"
  fi

  # ── Detect DSC overlay ──

  local dsc_overlay="full"
  local dsc_components
  dsc_components="$(oc get datasciencecluster -o jsonpath='{.items[0].spec.components}' 2>/dev/null || echo "")"
  if [[ -n "$dsc_components" ]]; then
    local managed_count
    managed_count="$(echo "$dsc_components" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for v in data.values() if isinstance(v, dict) and v.get('managementState') == 'Managed')
print(count)
" 2>/dev/null || echo "0")"
    if [[ "$managed_count" -le 2 ]]; then
      dsc_overlay="minimal"
    elif [[ "$managed_count" -le 5 ]]; then
      dsc_overlay="serving"
    fi
    echo "  Detected DSC profile: ~$managed_count managed components -> suggesting --dsc $dsc_overlay"
  fi

  # ── Auto-detect overlay: connected vs disconnected ──

  local detected_overlay="default"
  local idms_count icsp_count
  idms_count="$(oc get imagedigestmirrorset --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  icsp_count="$(oc get imagecontentsourcepolicy --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$idms_count" -gt 0 || "$icsp_count" -gt 0 || -n "$mirror_registry" ]]; then
    detected_overlay="disconnected"
    echo "  Detected environment: disconnected (IDMS/ICSP present)"
  else
    echo "  Detected environment: connected (no IDMS/ICSP found)"
  fi

  # ── Detect Git repo URL and branch ──

  local git_repo_url=""
  if command -v git &>/dev/null && git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null 2>&1; then
    git_repo_url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")"
  fi

  local git_branch=""
  if command -v git &>/dev/null; then
    git_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  fi
  [[ -z "$git_branch" ]] && git_branch="main"

  if [[ -n "$git_repo_url" ]]; then
    echo "  Detected Git remote: $git_repo_url"
    if [[ "$detected_overlay" == "disconnected" && "$git_repo_url" == *"github.com"* ]]; then
      echo ""
      echo "  ┌─────────────────────────────────────────────────────────────┐"
      echo "  │  WARNING: Disconnected cluster detected but Git remote     │"
      echo "  │  points to github.com. ArgoCD will NOT be able to reach    │"
      echo "  │  public Git from an air-gapped cluster.                    │"
      echo "  │                                                            │"
      echo "  │  You MUST edit configure-command.sh and set REPO_URL to    │"
      echo "  │  your internal Git server before running it.               │"
      echo "  │  See: docs/disconnected.md for internal Git requirements.  │"
      echo "  └─────────────────────────────────────────────────────────────┘"
      echo ""
    fi
  else
    echo "  WARN  Could not detect Git remote URL (set --repo manually)"
  fi
  echo "  Detected Git branch: $git_branch"

  # ── Detect RHOAI channel ──

  local rhoai_channel
  rhoai_channel="$(oc get sub rhods-operator -n redhat-ods-operator -o jsonpath='{.spec.channel}' 2>/dev/null || echo "")"
  [[ -z "$rhoai_channel" ]] && rhoai_channel="fast"
  echo "  Detected RHOAI channel: $rhoai_channel"

  # ── Generate configure.sh command ──

  local configure_cmd="$output_dir/configure-command.sh"
  local registry_line=""
  local registry_needs_edit=false
  if [[ -n "$mirror_registry" ]]; then
    registry_line="  --registry $mirror_registry \\"
  elif [[ "$detected_overlay" == "disconnected" ]]; then
    registry_line="  --registry REPLACE_WITH_YOUR_MIRROR_REGISTRY \\"
    registry_needs_edit=true
    echo ""
    echo "  WARN  Could not auto-detect mirror registry from IDMS/ICSP."
    echo "        You MUST edit configure-command.sh and set --registry before running."
  fi

  local repo_arg
  if [[ -n "$git_repo_url" ]]; then
    repo_arg="$git_repo_url"
  else
    repo_arg="YOUR_GIT_REPO_URL"
  fi

  # Use a relative channels path so it works from the repo root
  local channels_relpath
  channels_relpath="${channels_file#"$REPO_ROOT/"}"

  cat > "$configure_cmd" <<CMDEOF
#!/usr/bin/env bash
# Auto-generated configure.sh command based on cluster state
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Review and adjust before running

set -euo pipefail

# Repo root (baked at generation time)
REPO_ROOT="${REPO_ROOT}"
cd "\$REPO_ROOT"

REPO_URL="${repo_arg}"
REGISTRY_PLACEHOLDER="${registry_needs_edit}"

# Safety check: ensure repo URL is set
if [[ "\$REPO_URL" == "YOUR_GIT_REPO_URL" || -z "\$REPO_URL" ]]; then
  echo "Error: Edit this file and set REPO_URL to your Git repository URL."
  echo "       This must be reachable from inside the OpenShift cluster."
  exit 1
fi

# Safety check: ensure registry is set for disconnected
if [[ "\$REGISTRY_PLACEHOLDER" == "true" ]]; then
  if grep -q 'REPLACE_WITH_YOUR_MIRROR_REGISTRY' "\${BASH_SOURCE[0]}"; then
    echo "Error: Edit this file and replace REPLACE_WITH_YOUR_MIRROR_REGISTRY"
    echo "       with your actual mirror registry URL (e.g. myregistry.example.com:5000)."
    exit 1
  fi
fi

echo "Running configure.sh from: \$REPO_ROOT"
echo ""

./scripts/configure.sh \\
  --repo "\$REPO_URL" \\
  --branch "$git_branch" \\
  --overlay "$detected_overlay" \\
  --channel "$rhoai_channel" \\
  --dsc "$dsc_overlay" \\
  --catalog-source "$rhoai_src" \\
  --certified-catalog-source "$gpu_src" \\
${registry_line:+$registry_line
}  --operator-channels "$channels_relpath"

echo ""
echo "Configuration complete. Next steps:"
echo "  1. Verify alignment:  ./scripts/adopt.sh verify"
$(if [[ "$detected_overlay" == "disconnected" ]]; then
cat <<'DISC_STEPS'
echo "  2. Validate config:   ./scripts/configure.sh validate disconnected"
echo "  3. Preflight cluster: ./scripts/configure.sh preflight disconnected"
echo "  4. Commit changes:    git add -A && git commit -m 'Align for GitOps adoption'"
echo "  5. Push to remote:    git push"
echo "  6. Bootstrap ArgoCD:  until oc apply -k bootstrap/overlays/disconnected; do sleep 10; done"
DISC_STEPS
else
cat <<CONN_STEPS
echo "  2. Commit changes:    git add -A && git commit -m 'Align for GitOps adoption'"
echo "  3. Push to remote:    git push"
echo "  4. Bootstrap ArgoCD:  until oc apply -k bootstrap/overlays/$detected_overlay; do sleep 10; done"
CONN_STEPS
fi)
CMDEOF
  chmod +x "$configure_cmd"
  echo "  Created: $(basename "$configure_cmd")"

  echo ""
  echo "  Export complete. Review the files in $output_dir/"
  echo ""
  echo "  Next steps:"
  if [[ "$repo_arg" == "YOUR_GIT_REPO_URL" ]]; then
    echo "    1. Edit $configure_cmd and set REPO_URL to your Git repo URL"
    echo "       (must be reachable from inside the cluster)"
    echo "    2. Review operator-channels.conf and adjust if needed"
    echo "    3. Run the generated configure command:"
    echo "       bash $configure_cmd"
  else
    echo "    1. Review operator-channels.conf and adjust if needed"
    echo "    2. Verify the Git URL is reachable from the cluster:"
    echo "       $repo_arg"
    echo "    3. Run the generated configure command:"
    echo "       bash $configure_cmd"
  fi
  echo "    4. Verify: ./scripts/adopt.sh verify"
  if [[ "$detected_overlay" == "disconnected" ]]; then
    echo ""
    echo "  Disconnected environment — also run these checks before bootstrap:"
    echo "    5. Validate config:   ./scripts/configure.sh validate disconnected"
    echo "    6. Preflight cluster: ./scripts/configure.sh preflight disconnected"
    echo "    7. Diagnose issues:   ./scripts/configure.sh diagnose"
  fi
  echo ""
}

# ─── Subcommand: verify ──────────────────────────────────────────────────────

cmd_verify() {
  require_oc
  require_python3

  header "Verify GitOps Alignment"
  echo ""
  echo "  Comparing Git repo state with live cluster..."
  echo ""

  local pass=0 fail=0 warn=0

  # ── Check 0: cluster-config.yaml has real values ──

  echo "  ── Repository Configuration ──"
  echo ""

  # Detect local git remote for cross-check
  local local_git_remote=""
  if command -v git &>/dev/null; then
    local_git_remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")"
  fi

  local config_found=false
  for overlay_dir in "$REPO_ROOT"/bootstrap/overlays/*/; do
    local cfg="$overlay_dir/cluster-config.yaml"
    [[ -f "$cfg" ]] || continue

    local cfg_repo cfg_branch
    cfg_repo="$(grep '^[[:space:]]*repoURL:' "$cfg" 2>/dev/null | sed 's/.*repoURL:[[:space:]]*//' | tr -d '"' || true)"
    cfg_branch="$(grep '^[[:space:]]*targetRevision:' "$cfg" 2>/dev/null | sed 's/.*targetRevision:[[:space:]]*//' | tr -d '"' || true)"
    local overlay_name
    overlay_name="$(basename "$overlay_dir")"

    if [[ -z "$cfg_repo" || "$cfg_repo" == *"YOUR-ORG"* || "$cfg_repo" == *"YOUR_GIT"* || "$cfg_repo" == *"PLACEHOLDER"* || "$cfg_repo" == *"REPLACE"* ]]; then
      echo "  FAIL  ${overlay_name}/cluster-config.yaml: repoURL not configured"
      echo "        Current value: ${cfg_repo:-<empty>}"
      echo "        Fix: Run configure.sh --repo <your-git-url> or bash adoption-export/configure-command.sh"
      fail=$((fail + 1))
    elif [[ -n "$local_git_remote" && "$cfg_repo" != "$local_git_remote" ]]; then
      echo "  WARN  ${overlay_name}/cluster-config.yaml: repoURL differs from local git remote"
      echo "        cluster-config: $cfg_repo"
      echo "        git remote:     $local_git_remote"
      echo "        Ensure the cluster-config URL is reachable from inside the cluster."
      warn=$((warn + 1))
    else
      echo "  PASS  ${overlay_name}/cluster-config.yaml: repoURL=$cfg_repo"
      pass=$((pass + 1))
    fi

    if [[ -z "$cfg_branch" ]]; then
      echo "  WARN  ${overlay_name}/cluster-config.yaml: targetRevision is empty"
      warn=$((warn + 1))
    else
      echo "  PASS  ${overlay_name}/cluster-config.yaml: branch=$cfg_branch"
      pass=$((pass + 1))
    fi
    config_found=true
  done

  if ! $config_found; then
    echo "  FAIL  No cluster-config.yaml found in any overlay"
    echo "        Run configure.sh first to create the configuration"
    fail=$((fail + 1))
  fi
  echo ""

  # ── Check 1: Subscription channel/source alignment ──

  echo "  ── Subscription Alignment ──"
  echo ""

  for entry in "${OPERATOR_ENTRIES[@]}"; do
    IFS='|' read -r git_dir expected_sub expected_ns <<< "$entry"

    local cluster_ch cluster_src
    cluster_ch="$(oc get sub "$expected_sub" -n "$expected_ns" -o jsonpath='{.spec.channel}' 2>/dev/null || echo "")"
    cluster_src="$(oc get sub "$expected_sub" -n "$expected_ns" -o jsonpath='{.spec.source}' 2>/dev/null || echo "")"

    [[ -z "$cluster_ch" ]] && continue

    local git_ch="" git_src=""
    local ch_patch="$REPO_ROOT/components/operators/$git_dir/patch-channel.yaml"
    local src_patch="$REPO_ROOT/components/operators/$git_dir/patch-source.yaml"
    [[ -f "$ch_patch" ]] && git_ch="$(grep 'value:' "$ch_patch" 2>/dev/null | head -1 | sed 's/.*value:[[:space:]]*//' | tr -d '"[:space:]' || true)"
    [[ -f "$src_patch" ]] && git_src="$(grep 'value:' "$src_patch" 2>/dev/null | head -1 | sed 's/.*value:[[:space:]]*//' | tr -d '"[:space:]' || true)"

    local ch_ok=true src_ok=true
    [[ -n "$git_ch" && "$cluster_ch" != "$git_ch" ]] && ch_ok=false
    [[ -n "$git_src" && "$cluster_src" != "$git_src" ]] && src_ok=false

    if $ch_ok && $src_ok; then
      echo "  PASS  $git_dir: channel=$cluster_ch source=$cluster_src"
      pass=$((pass + 1))
    else
      echo "  FAIL  $git_dir:"
      $ch_ok || echo "        Channel: cluster=$cluster_ch git=$git_ch"
      $src_ok || echo "        Source:  cluster=$cluster_src git=$git_src"
      fail=$((fail + 1))
    fi
  done

  # ── Check 2: OperatorGroup alignment ──

  echo ""
  echo "  ── OperatorGroup Alignment ──"
  echo ""

  for entry in "${OPERATOR_ENTRIES[@]}"; do
    IFS='|' read -r git_dir _sub expected_ns <<< "$entry"
    [[ "$expected_ns" == "openshift-operators" ]] && continue

    local cluster_og
    cluster_og="$(oc get operatorgroup -n "$expected_ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
    [[ -z "$cluster_og" ]] && continue

    local git_og=""
    local og_file="$REPO_ROOT/components/operators/$git_dir/operatorgroup.yaml"
    if [[ -f "$og_file" ]]; then
      git_og="$(grep '^[[:space:]]*name:' "$og_file" | head -1 | sed 's/.*name:[[:space:]]*//' | tr -d '"')"
    fi
    local og_patch="$REPO_ROOT/components/operators/$git_dir/patch-operatorgroup-name.yaml"
    if [[ -f "$og_patch" ]]; then
      local patched_name
      patched_name="$(grep 'value:' "$og_patch" 2>/dev/null | head -1 | sed 's/.*value:[[:space:]]*//' | tr -d '"[:space:]' || true)"
      [[ -n "$patched_name" ]] && git_og="$patched_name"
    fi

    if [[ -n "$git_og" ]]; then
      if [[ "$cluster_og" == "$git_og" ]]; then
        echo "  PASS  $expected_ns: $cluster_og"
        pass=$((pass + 1))
      else
        echo "  FAIL  $expected_ns: cluster='$cluster_og' git='$git_og'"
        echo "        Create patch-operatorgroup-name.yaml or rename in Git"
        fail=$((fail + 1))
      fi
    fi
  done

  # ── Check 3: DSC component alignment ──

  echo ""
  echo "  ── DataScienceCluster Component Alignment ──"
  echo ""

  local cluster_dsc_json
  cluster_dsc_json="$(oc get datasciencecluster -o json 2>/dev/null || echo '{"items":[]}')"
  local cluster_dsc_count
  cluster_dsc_count="$(echo "$cluster_dsc_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))" 2>/dev/null || echo "0")"

  if [[ "$cluster_dsc_count" -eq 0 ]]; then
    echo "  INFO  No DataScienceCluster found — will be created by GitOps"
    warn=$((warn + 1))
  else
    local git_dsc="$REPO_ROOT/components/instances/rhoai-instance/base/datasciencecluster.yaml"
    if [[ -f "$git_dsc" ]]; then
      local dsc_diff
      dsc_diff="$(python3 -c "
import sys, json, re

# Parse cluster DSC
cluster = json.load(sys.stdin)
if not cluster.get('items'):
    sys.exit(0)
cluster_comps = cluster['items'][0].get('spec',{}).get('components',{})

# Parse Git DSC without PyYAML — extract managementState lines
git_comps = {}
current_comp = None
with open('$git_dsc') as f:
    in_components = False
    for line in f:
        stripped = line.rstrip()
        if stripped == '  components:':
            in_components = True
            continue
        if not in_components:
            continue
        # Top-level component (4-space indent, ends with colon)
        m = re.match(r'^    ([a-zA-Z][a-zA-Z0-9]*):$', stripped)
        if m:
            current_comp = m.group(1)
            continue
        # managementState at 6-space indent (direct child of component)
        m = re.match(r'^      managementState:\s*(\S+)', stripped)
        if m and current_comp:
            git_comps[current_comp] = m.group(1)
            current_comp = None
            continue
        # Non-indented line means we left spec.components
        if stripped and not stripped.startswith('    '):
            in_components = False

diffs = 0
for comp in sorted(set(list(cluster_comps.keys()) + list(git_comps.keys()))):
    c_state = 'absent'
    g_state = 'absent'
    if comp in cluster_comps:
        c_state = cluster_comps[comp].get('managementState', 'Unknown') if isinstance(cluster_comps[comp], dict) else str(cluster_comps[comp])
    if comp in git_comps:
        g_state = git_comps[comp]
    if c_state != g_state:
        print(f'  WARN  {comp}: cluster={c_state} git={g_state}')
        diffs += 1
if diffs == 0:
    print('  PASS  All DSC component states match')
else:
    print(f'')
    print(f'  {diffs} component(s) differ. ArgoCD will change them to match Git.')
    print(f'  If this is not desired, choose a different --dsc overlay or customize dev.')
print(f'DIFFS={diffs}')
" <<< "$cluster_dsc_json" 2>/dev/null)"

      if [[ -n "$dsc_diff" ]]; then
        echo "$dsc_diff" | grep -v '^DIFFS=' || true
        local dsc_diff_count
        dsc_diff_count="$(echo "$dsc_diff" | grep '^DIFFS=' | sed 's/DIFFS=//' || echo "0")"
        if [[ "${dsc_diff_count:-0}" -gt 0 ]]; then
          warn=$((warn + 1))
        else
          pass=$((pass + 1))
        fi
      else
        echo "  WARN  Could not compare DSC (python3 required)"
        warn=$((warn + 1))
      fi
    else
      echo "  WARN  Git DSC file not found at components/instances/rhoai-instance/base/"
      warn=$((warn + 1))
    fi
  fi

  # ── Check 4: ArgoCD Applications health ──

  echo ""
  echo "  ── ArgoCD Applications ──"
  echo ""

  local apps_json
  apps_json="$(oc get applications.argoproj.io -n openshift-gitops -o json 2>/dev/null || echo '{"items":[]}')"
  local app_count
  app_count="$(echo "$apps_json" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))" 2>/dev/null || echo "0")"

  if [[ "$app_count" -eq 0 ]]; then
    echo "  INFO  No ArgoCD Applications found — GitOps not yet bootstrapped"
    warn=$((warn + 1))
  else
    echo "$apps_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
synced = 0
not_synced = 0
for app in data.get('items', []):
    name = app['metadata']['name']
    sync = app.get('status',{}).get('sync',{}).get('status','Unknown')
    health = app.get('status',{}).get('health',{}).get('status','Unknown')
    if sync == 'Synced' and health == 'Healthy':
        synced += 1
    else:
        not_synced += 1
        print(f'  WARN  {name}: sync={sync} health={health}')
print(f'')
print(f'  Total: {synced + not_synced} apps, {synced} synced+healthy, {not_synced} need attention')
" 2>/dev/null || echo "  WARN  Could not parse applications (python3 required)"
  fi

  # ── Summary ──

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  if [[ $fail -eq 0 && $warn -eq 0 ]]; then
    echo "  VERIFY: PASSED — Git repo is aligned with cluster ($pass checks passed)"
    echo ""
    echo "  Safe to bootstrap or re-sync ArgoCD."
  elif [[ $fail -eq 0 ]]; then
    echo "  VERIFY: PASSED with $warn warning(s) ($pass checks passed)"
    echo ""
    echo "  Review warnings above. Safe to bootstrap if warnings are acceptable."
  else
    echo "  VERIFY: FAILED — $fail misalignment(s) found, $warn warning(s)"
    echo ""
    echo "  Fix mismatches before bootstrapping ArgoCD to avoid conflicts."
    echo "  1. Re-export:   ./scripts/adopt.sh export"
    echo "  2. Re-configure: bash adoption-export/configure-command.sh"
    echo "  3. Re-verify:    ./scripts/adopt.sh verify"
  fi
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  [[ $fail -gt 0 ]] && exit 1 || true
}

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
  local exit_code="${1:-0}"
  cat <<USAGE
Usage: $0 <command> [options]

Adopt a manually installed RHOAI deployment into GitOps management.

Commands:
  audit              Discover the current cluster state and compare with Git repo.
                     Shows operator subscriptions, channels, catalog sources,
                     OperatorGroup names, DSC state, and identifies mismatches.
                     This is read-only — it does not modify the cluster or Git.

  export [dir]       Export current cluster state to a directory for Git alignment.
                     Auto-detects: Git remote, branch, RHOAI channel, overlay,
                     DSC profile, mirror registry, and catalog sources.
                     Generates a ready-to-run configure-command.sh.
                     Default output dir: adoption-export/

  verify             Verify that the Git repo is aligned with the live cluster.
                     Checks repo config, subscription channels/sources,
                     OperatorGroup names, DSC components, and ArgoCD health.

Workflow:
  1. Run 'audit' to see what's installed and where it differs from Git
  2. Run 'export' to capture the current state
  3. Review the exported files and run the generated configure command
  4. Run 'verify' to confirm alignment
  5. Bootstrap GitOps:
     until oc apply -k bootstrap/overlays/<overlay>; do sleep 10; done

Prerequisites:
  - oc CLI logged in as cluster-admin
  - python3 (for JSON parsing)
  - RHOAI already installed on the cluster

Full guide: docs/adoption.md

Examples:
  $0 audit
  $0 export
  $0 export /tmp/my-cluster-state
  $0 verify
USAGE
  exit "$exit_code"
}

# ─── Dispatch ────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
  audit)   cmd_audit ;;
  export)  cmd_export "${1:-}" ;;
  verify)  cmd_verify ;;
  --help|-h|help) usage ;;
  *)       echo "Error: Unknown command: $COMMAND"; echo; usage 1 ;;
esac
