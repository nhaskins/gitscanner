#!/usr/bin/env bash
#
# Scan a single repository with Gitleaks and TruffleHog.
# Usage: ./scripts/scan-repo.sh [--filesystem-only] repos/<name>
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPORTS_ROOT="${WORKSPACE_ROOT}/reports"

SCAN_MODE="git"
REPO_PATH=""

usage() {
  cat <<'EOF'
Usage: scan-repo.sh [--filesystem-only] <repo-path>

Scan a repository for leaked secrets using Gitleaks and TruffleHog.

Options:
  --filesystem-only   Scan working tree files only (skip git history)
  -h, --help          Show this help message

Examples:
  ./scripts/scan-repo.sh repos/my-project
  ./scripts/scan-repo.sh --filesystem-only repos/my-project
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --filesystem-only)
      SCAN_MODE="filesystem"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "${REPO_PATH}" ]]; then
        echo "Error: unexpected extra argument: $1" >&2
        usage >&2
        exit 1
      fi
      REPO_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "${REPO_PATH}" ]]; then
  echo "Error: repository path is required." >&2
  usage >&2
  exit 1
fi

# Resolve relative paths from the workspace root.
if [[ "${REPO_PATH}" != /* ]]; then
  REPO_PATH="${WORKSPACE_ROOT}/${REPO_PATH}"
fi

if [[ ! -d "${REPO_PATH}" ]]; then
  echo "Error: repository path does not exist: ${REPO_PATH}" >&2
  exit 1
fi

ABS_REPO_PATH="$(cd "${REPO_PATH}" && pwd)"
REPO_NAME="$(basename "${ABS_REPO_PATH}")"
REPORT_DIR="${REPORTS_ROOT}/${REPO_NAME}"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "${REPORT_DIR}"

echo "============================================================"
echo " Secret scan: ${REPO_NAME}"
echo "============================================================"
echo "Repository : ${ABS_REPO_PATH}"
echo "Reports    : ${REPORT_DIR}"
echo "Mode       : ${SCAN_MODE}"
echo "Started    : ${TIMESTAMP}"
echo ""

GITLEAKS_EXIT=0
TRUFFLEHOG_EXIT=0

# --- Gitleaks ---
# `gitleaks detect` scans git history by default.
# Use --no-git for a filesystem-only scan of the current tree.
echo "--- Gitleaks ---"
GITLEAKS_ARGS=(
  detect
  --source "${ABS_REPO_PATH}"
  --verbose
  --report-format json
  --report-path "${REPORT_DIR}/gitleaks.json"
)

if [[ "${SCAN_MODE}" == "filesystem" ]]; then
  GITLEAKS_ARGS+=(--no-git)
  echo "Scanning working tree only (--no-git)."
else
  echo "Scanning full git history."
fi

set +e
gitleaks "${GITLEAKS_ARGS[@]}" 2>&1 | tee "${REPORT_DIR}/gitleaks.log"
GITLEAKS_EXIT=${PIPESTATUS[0]}
set -e

if [[ ${GITLEAKS_EXIT} -eq 0 ]]; then
  echo "Gitleaks: no leaks reported."
else
  echo "Gitleaks: finished with exit code ${GITLEAKS_EXIT} (findings or errors — review gitleaks.json)."
fi

echo ""

# --- TruffleHog ---
# `trufflehog git file://...` scans local git history.
# `trufflehog filesystem` scans the current working tree.
# --only-verified reduces noise by reporting only verified live secrets.
# --no-update avoids auto-updater failures in container environments.
echo "--- TruffleHog ---"
set +e
if [[ "${SCAN_MODE}" == "filesystem" ]]; then
  echo "Scanning working tree only (filesystem mode)."
  trufflehog filesystem "${ABS_REPO_PATH}" \
    --only-verified \
    --no-update \
    --json > "${REPORT_DIR}/trufflehog.json" \
    2> "${REPORT_DIR}/trufflehog.log"
else
  echo "Scanning full git history (file:// local path)."
  trufflehog git "file://${ABS_REPO_PATH}" \
    --only-verified \
    --no-update \
    --json > "${REPORT_DIR}/trufflehog.json" \
    2> "${REPORT_DIR}/trufflehog.log"
fi
TRUFFLEHOG_EXIT=$?
set -e

if [[ ${TRUFFLEHOG_EXIT} -eq 0 ]]; then
  echo "TruffleHog: no verified secrets reported."
else
  echo "TruffleHog: finished with exit code ${TRUFFLEHOG_EXIT} (findings or errors — review trufflehog.json)."
fi

# Write a human-readable summary alongside JSON reports.
{
  echo "Scan summary"
  echo "============"
  echo "Timestamp : ${TIMESTAMP}"
  echo "Repository: ${ABS_REPO_PATH}"
  echo "Mode      : ${SCAN_MODE}"
  echo "Gitleaks  : exit ${GITLEAKS_EXIT} -> ${REPORT_DIR}/gitleaks.json"
  echo "TruffleHog: exit ${TRUFFLEHOG_EXIT} -> ${REPORT_DIR}/trufflehog.json"
} > "${REPORT_DIR}/scan-summary.txt"

echo ""
echo "============================================================"
echo " Scan complete"
echo "============================================================"
echo "Summary : ${REPORT_DIR}/scan-summary.txt"
echo "Gitleaks: ${REPORT_DIR}/gitleaks.json"
echo "TruffleHog: ${REPORT_DIR}/trufflehog.json"
echo ""

if [[ ${GITLEAKS_EXIT} -ne 0 || ${TRUFFLEHOG_EXIT} -ne 0 ]]; then
  echo "WARNING: Review reports before making this repository public."
  exit 1
fi

echo "No issues reported by either scanner."
exit 0
