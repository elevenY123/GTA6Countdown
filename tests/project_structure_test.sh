#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node "$root/tests/validate_project_structure.js" "$root"
