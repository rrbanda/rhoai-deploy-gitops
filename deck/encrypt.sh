#!/bin/bash
# Encrypts deck/index.html for password-protected GitHub Pages deployment.
# The password is NEVER committed to git — share it out-of-band (Slack, email, etc.).
#
# Usage:
#   ./encrypt.sh                          # prompts for password interactively
#   DECK_PASSWORD=xyz ./encrypt.sh        # uses env var
#
# Output: encrypted/index.html (committed to git, deployed via GitHub Pages)

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f index.html ]; then
  echo "Error: index.html not found in deck/"
  exit 1
fi

mkdir -p encrypted

PASSWORD_ARGS=()
if [ -n "${DECK_PASSWORD:-}" ]; then
  PASSWORD_ARGS=(--password "$DECK_PASSWORD")
fi

npx staticrypt index.html \
  "${PASSWORD_ARGS[@]}" \
  --directory encrypted \
  --config false \
  --short \
  --remember 7 \
  --template-title "RHOAI 3.5 EA2 — GitOps Deployment" \
  --template-instructions "Enter the presentation password to continue." \
  --template-color-primary "#EE0000" \
  --template-color-secondary "#151515"

echo ""
echo "Encrypted → deck/encrypted/index.html"
echo "Commit and push to deploy via GitHub Pages."
echo "DO NOT commit the password anywhere."
