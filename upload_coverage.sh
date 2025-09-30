#!/usr/bin/env bash
set -euo pipefail

API_BASE="https://api.codeant.ai/pr/analysis/coverage"
VCS_BASE=""
USAGE="$0 -t <access_token> -r <repo_name> -c <commit_id> -f <coverage_file> -p <platform> [-m <module>] [-b <branch>] [-u <vcs_base_url>]"

usage() {
  cat <<EOF
Usage: $USAGE
  -t TOKEN       Your service access token
  -r REPO_NAME   Repo slug (e.g. myorg/myrepo)
  -c COMMIT_ID   Commit SHA
  -f FILE        Path to coverage.xml
  -p PLATFORM    The git provider (e.g. github, bitbucket, gitlab)
  -m MODULE      (optional) Module name in a monorepo (e.g. frontend)
  -b BRANCH      (optional) Branch name
  -u VCS_URL     (optional) Custom VCS base URL (e.g. https://github.enterprise.com for GitHub Enterprise)
EOF
  exit 1
}

# 1) Parse flags
MODULE=""
BRANCH=""
VCS_BASE=""
while getopts ":t:r:c:f:p:m:b:u:" opt; do
  case "$opt" in
    t) ACCESS_TOKEN=$OPTARG ;;
    r) REPO_NAME=$OPTARG    ;;
    c) COMMIT_ID=$OPTARG    ;;
    f) COVERAGE_FILE=$OPTARG;;
    p) PLATFORM=$OPTARG     ;;
    m) MODULE=$OPTARG       ;;
    b) BRANCH=$OPTARG       ;;
    u) VCS_BASE=$OPTARG     ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

# 2) Validate required parameters
if [[ -z "${ACCESS_TOKEN:-}" || -z "${REPO_NAME:-}" || -z "${COMMIT_ID:-}" || -z "${COVERAGE_FILE:-}" || -z "${PLATFORM:-}" ]]; then
  usage
fi
if [[ ! -f "$COVERAGE_FILE" ]]; then
  echo "Error: coverage file not found: $COVERAGE_FILE" >&2
  exit 2
fi

# 3) Presign
echo "Requesting presigned URLs..."
json_payload="{\"repo\":\"$REPO_NAME\",\"commit_id\":\"$COMMIT_ID\",\"access_token\":\"$ACCESS_TOKEN\",\"platform\":\"$PLATFORM\""
if [[ -n "$MODULE" ]]; then
  json_payload="$json_payload,\"module\":\"$MODULE\""
fi
if [[ -n "$BRANCH" ]]; then
  json_payload="$json_payload,\"branch\":\"$BRANCH\""
fi
if [[ -n "$VCS_BASE" ]]; then
  json_payload="$json_payload,\"vcs_base_url\":\"$VCS_BASE\""
fi
json_payload="$json_payload}"

presign_resp=$(curl -sS -X POST "${API_BASE}/presign" \
  -H "Content-Type: application/json" \
  -d "$json_payload")

# 4) Extract the presigned URL
coverage_url=$(printf '%s' "$presign_resp" | python3 -c 'import sys,json;print(json.load(sys.stdin)["coverage_url"])')
if [[ -z "$coverage_url" ]]; then
  echo "Error: no coverage_url in presign response" >&2
  echo "$presign_resp" >&2
  exit 3
fi
echo "Presigned URLs received."

# 5) Upload coverage.xml
echo "Uploading coverage.xml to S3..."
curl -sS -X PUT "$coverage_url" \
  -H "Content-Type: application/xml" \
  --upload-file "$COVERAGE_FILE"

# echo "Result: $complete_resp"
echo "Notifying service to set status/comment..."
json_payload="{\"repo\":\"$REPO_NAME\",\"commit_id\":\"$COMMIT_ID\",\"access_token\":\"$ACCESS_TOKEN\",\"platform\":\"$PLATFORM\""
if [[ -n "$MODULE" ]]; then
  json_payload="$json_payload,\"module\":\"$MODULE\""
fi
if [[ -n "$BRANCH" ]]; then
  json_payload="$json_payload,\"branch\":\"$BRANCH\""
fi
if [[ -n "$VCS_BASE" ]]; then
  json_payload="$json_payload,\"vcs_base_url\":\"$VCS_BASE\""
fi
json_payload="$json_payload}"

complete_resp=$(curl -sS -w "\n%{http_code}" -X POST "${API_BASE}/complete" \
  -H "Content-Type: application/json" \
  -d "$json_payload")

# Extract response body and status code
response_body=$(echo "$complete_resp" | head -n -1)
status_code=$(echo "$complete_resp" | tail -n 1)

echo "Result: $response_body"

# Check for 4XX/5XX and exit with error
if [[ "$status_code" -ge 400 ]]; then
  echo "Error: Request failed with HTTP $status_code" >&2
  echo "Response: $response_body" >&2
  exit 4
fi
