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
  --remember 7

# Apply Red Hat branding to the password page
OUT="encrypted/index.html"

python3 - "$OUT" <<'PYEOF'
import sys, re
f = sys.argv[1]
html = open(f).read()

# Title
html = html.replace('<title>Protected Page</title>',
  '<title>RHOAI 3.5 EA2 — GitOps Deployment</title>')

# Google Fonts
html = html.replace(
  '<meta name="viewport" content="width=device-width, initial-scale=1" />',
  '<meta name="viewport" content="width=device-width, initial-scale=1" />\n'
  '        <link rel="preconnect" href="https://fonts.googleapis.com">\n'
  '        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
  '        <link href="https://fonts.googleapis.com/css2?family=Red+Hat+Display:wght@400;500;700;900&family=Red+Hat+Mono:wght@400;500;700&display=swap" rel="stylesheet">')

# Body background
html = html.replace('background: #76B852;', 'background: #151515;')
html = html.replace("font-family: \"Arial\", sans-serif;",
  'font-family: "Red Hat Display", -apple-system, "Segoe UI", system-ui, sans-serif;')

# Form card
html = html.replace('background: #ffffff;', 'background: #1a1a1a;')
html = html.replace(
  'box-shadow: 0 0 20px 0 rgba(0, 0, 0, 0.2), 0 5px 5px 0 rgba(0, 0, 0, 0.24);',
  'box-shadow: 0 0 40px 0 rgba(238,0,0,0.08), 0 8px 24px 0 rgba(0,0,0,0.4); border-radius: 12px; border: 1px solid #333;')

# Input field
html = html.replace('background: #f2f2f2;', 'background: #252525;')
html = re.sub(
  r'(\.staticrypt-password-container\s*\{[^}]*?)border: 0;',
  r'\1border: 1px solid #444; border-radius: 6px;', html, count=1)

# Button
html = html.replace('background: #4CAF50;', 'background: #EE0000;', 1)
html = html.replace('background: #4CAF50;', 'background: #CC0000;', 1)

# HR
html = html.replace('border-top: 1px solid #eee;', 'border-top: 1px solid #333;')

# Spinner
html = html.replace('border: 0.25em solid gray;', 'border: 0.25em solid #333;')
html = html.replace('border-right-color: transparent;', 'border-right-color: #EE0000;')

# Body element background
html = re.sub(
  r'(\.staticrypt-body\s*\{[^}]*?)margin: 0;',
  r'\1margin: 0; background: #151515;', html, count=1)

# Title + instructions branding
html = html.replace(
  '<p class="staticrypt-title">Protected Page</p>\n                        <p></p>',
  '<div style="font-family:\'Red Hat Mono\',monospace; font-size:0.65em; font-weight:700; '
  'letter-spacing:0.2em; text-transform:uppercase; color:#EE0000; margin-bottom:0.75em;">'
  'RHOAI 3.5 EA2 &middot; GITOPS</div>\n'
  '                        <p class="staticrypt-title">Deploying Red Hat OpenShift AI with GitOps</p>\n'
  '                        <p style="color:#8a8a8a; font-size:0.85em; margin-top:0.5em;">'
  'Enter the presentation password to continue.</p>')

# Text colors for dark theme
html = re.sub(
  r'(\.staticrypt-title\s*\{[^}]*?)font-size: 1\.5em;',
  r'\1font-size: 1.35em; font-weight: 700; color: #ffffff; line-height: 1.3;', html, count=1)
html = re.sub(
  r'(\.staticrypt-instructions\s*\{[^}]*?)\}',
  r'\1 color: #d2d2d2; }', html, count=1)

# Eye icon invert for dark bg
html = re.sub(
  r'(\.staticrypt-toggle-password-visibility\s*\{[^}]*?)width: 20px;',
  r'\1width: 20px; filter: invert(1);', html, count=1)

# Remember label color
html = re.sub(
  r'(label\.staticrypt-remember\s*\{[^}]*?)\}',
  r'\1 color: #8a8a8a; font-size: 0.85em; }', html, count=1)

# Password input text color
html = re.sub(
  r'(\.staticrypt-form input\[type="password"\],[^{]*?\{[^}]*?)width: 100%;',
  r'\1width: 100%; color: #ffffff; font-family: "Red Hat Mono", monospace;', html, count=1)

# Button styling
html = re.sub(
  r'(\.staticrypt-form \.staticrypt-decrypt-button\s*\{[^}]*?)cursor: pointer;',
  r'\1cursor: pointer; border-radius: 6px; font-weight: 700; '
  'font-family: "Red Hat Display", sans-serif; letter-spacing: 0.08em; '
  'transition: background 180ms, box-shadow 180ms;', html, count=1)

# Checkbox accent
html = re.sub(
  r'(\.staticrypt-remember input\[type="checkbox"\]\s*\{[^}]*?)\}',
  r'\1 accent-color: #EE0000; }', html, count=1)

open(f, 'w').write(html)
PYEOF

echo ""
echo "Encrypted → deck/encrypted/index.html (with Red Hat branding)"
echo "Commit and push to deploy via GitHub Pages."
echo "DO NOT commit the password anywhere."
