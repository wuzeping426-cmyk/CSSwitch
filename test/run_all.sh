#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "== python unittest =="
python3 -m unittest discover -s test -p 'test_*.py' -v
echo "== node --test =="
node --test test/test_make_virtual_oauth.mjs
if command -v zsh >/dev/null 2>&1; then
  echo "== bash/zsh scripts =="
  bash test/test_scripts.sh
  echo "== bash/zsh ops scripts (doctor/verify-proxy/self-test) =="
  bash test/test_ops_scripts.sh
else
  echo "== bash/zsh scripts skipped (zsh is not installed; macOS-only test group) =="
fi
echo "ALL GREEN"
