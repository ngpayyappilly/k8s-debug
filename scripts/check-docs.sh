#!/usr/bin/env bash
# Fail if a tool the image ships (the TOOLS list in smoke-test.sh) has no
# documentation section. A tool is documented when some page under docs/tools/
# has a heading of the form:   ## `toolname`
set -euo pipefail

cd "$(dirname "$0")/.."

# Extract the TOOLS=( ... ) array from the smoke test.
tools=$(awk '/^TOOLS=\(/{f=1; next} f && /^\)/{exit} f' scripts/smoke-test.sh | sed 's/#.*//')

missing=0
for t in $tools; do
  if ! grep -rqE "^##+ \`${t}\`" docs/tools/; then
    echo "undocumented tool: ${t}  (add a '## \`${t}\`' section under docs/tools/)"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi
echo "docs cover all $(wc -w <<<"$tools" | tr -d ' ') tools"
