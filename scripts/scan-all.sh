#!/usr/bin/env bash
#
# Scan every direct child directory inside repos/.
# Usage: ./scripts/scan-all.sh [--filesystem-only]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPOS_DIR="${WORKSPACE_ROOT}/repos"
SCAN_REPO="${SCRIPT_DIR}/scan-repo.sh"

EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: scan-all.sh [--filesystem-only]

Run scan-repo.sh on every direct child folder inside repos/.

Options:
  --filesystem-only   Scan working tree files only (skip git history)
  -h, --help          Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filesystem-only)
      EXTRA_ARGS+=("$1")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "${REPOS_DIR}" ]]; then
  echo "Error: repos directory not found: ${REPOS_DIR}" >&2
  exit 1
fi

found=0
issues=0

# Loop over each direct child of repos/ (skip files like .gitkeep).
for repo_path in "${REPOS_DIR}"/*/; do
  [[ -d "${repo_path}" ]] || continue

  repo_name="$(basename "${repo_path}")"
  found=$((found + 1))

  echo ""
  echo "########################################################"
  echo "# [${found}] Scanning: ${repo_name}"
  echo "########################################################"

  # Continue the batch even when an individual repo reports findings.
  set +e
  "${SCAN_REPO}" "${EXTRA_ARGS[@]}" "${repo_path}"
  scan_exit=$?
  set -e

  if [[ ${scan_exit} -ne 0 ]]; then
    issues=$((issues + 1))
    echo "Note: ${repo_name} reported findings or errors (continuing batch)."
  fi
done

echo ""
echo "========================================================"
if [[ ${found} -eq 0 ]]; then
  echo "No repositories found in ${REPOS_DIR}"
  echo ""
  echo "Clone a candidate repo first, for example:"
  echo "  git clone https://github.com/you/your-repo.git repos/your-repo"
else
  echo "Batch scan complete"
  echo "Repositories scanned : ${found}"
  echo "With findings/errors : ${issues}"
  echo "Reports directory    : ${WORKSPACE_ROOT}/reports/"
fi
echo "========================================================"

# Always exit 0 so one bad repo does not stop review of the rest.
exit 0
