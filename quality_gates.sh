#!/usr/bin/env bash
# quality_gates.sh
#
# Trigger CodeAnt quality gate scans from a CI pipeline.
# Flags:
#   -a, --access-token                (required) repo token / PAT
#   -r, --repo                        (required) <org>/<repo>
#   -c, --commit-id                   (required) SHA to scan
#   -s, --service                     VCS provider (default: github)
#   -u, --base-url                    Base URL for VCS service (optional)
#   -o, --operation                   Operation: "start" or "results" (default: start)
#   -t, --timeout                     Timeout in seconds for polling results (default: 300)
#   -p, --poll-interval               Poll interval in seconds (default: 15)
#   -h, --help                        Show help
#
# Examples:
#   # Start a quality gate scan
#   ./quality_gates.sh -a "$GITHUB_TOKEN" -r "org/repo" \
#                      -c "$GITHUB_SHA" -s github -o start
#
#   # Poll for results
#   ./quality_gates.sh -a "$GITHUB_TOKEN" -r "org/repo" \
#                      -c "$GITHUB_SHA" -s github -o results
#
#   # Start scan and wait for results with custom timeout
#   ./quality_gates.sh -a "$GITHUB_TOKEN" -r "org/repo" \
#                      -c "$GITHUB_SHA" -s github -o results -t 600
#

set -euo pipefail

########################################
# 0. Helpers
########################################
usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit "$1"
}

fail() {
  echo "❌  $*" >&2
  exit 1
}

log() {
  echo "📝  $*"
}

########################################
# 1. Initialize variables
########################################
ACCESS_TOKEN=""
REPO=""
COMMIT_ID=""
SERVICE="github"
BASE_URL=""
OPERATION="start"
TIMEOUT=300
POLL_INTERVAL=15

########################################
# 2. Parse CLI flags
########################################
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--access-token)
      if [[ $# -lt 2 ]]; then
        fail "Option $1 requires an argument"
      fi
      ACCESS_TOKEN="$2"
      shift 2
      ;;
    -r|--repo)
      if [[ $# -lt 2 ]]; then
        fail "Option $1 requires an argument"
      fi
      REPO="$2"
      shift 2
      ;;
    -c|--commit-id)
      if [[ $# -lt 2 ]]; then
        fail "Option $1 requires an argument"
      fi
      COMMIT_ID="$2"
      shift 2
      ;;
    -s|--service)
      if [[ $# -lt 2 ]]; then
        fail "Option $1 requires an argument"
      fi
      SERVICE="$2"
      shift 2
      ;;
    -u|--base-url)
      if [[ $# -lt 2 ]]; then
        fail "Option $1 requires an argument"
      fi
      BASE_URL="$2"
      shift 2
      ;;
    -o|--operation)
      if [[ $# -lt 2 ]]; then
        fail "Option $1 requires an argument"
      fi
      OPERATION="$2"
      shift 2
      ;;
    -t|--timeout)
      if [[ $# -lt 2 ]]; then
        fail "Option $1 requires an argument"
      fi
      TIMEOUT="$2"
      shift 2
      ;;
    -p|--poll-interval)
      if [[ $# -lt 2 ]]; then
        fail "Option $1 requires an argument"
      fi
      POLL_INTERVAL="$2"
      shift 2
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

########################################
# 3. Validation
########################################
[[ -z "$ACCESS_TOKEN" ]] && fail "ACCESS_TOKEN is required (use -a)."
[[ -z "$REPO"         ]] && fail "REPO is required (use -r)."
[[ -z "$COMMIT_ID"    ]] && fail "COMMIT_ID is required (use -c)."

# Validate operation
if [[ "$OPERATION" != "start" && "$OPERATION" != "results" ]]; then
  fail "OPERATION must be either 'start' or 'results' (use -o)."
fi

# Validate numeric parameters
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -lt 1 ]]; then
  fail "TIMEOUT must be a positive integer."
fi

if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$POLL_INTERVAL" -lt 1 ]]; then
  fail "POLL_INTERVAL must be a positive integer."
fi

########################################
# 4. Static config
########################################
BASE_API_URL="https://api.codeant.ai"
START_URL="$BASE_API_URL/analysis/ci/quality-gates/scan/start"
RESULTS_URL="$BASE_API_URL/analysis/ci/quality-gates/scan/results"

########################################
# 5. Functions
########################################
start_scan() {
  log "Starting quality gate scan for $REPO@$COMMIT_ID"
  
  # Build JSON payload
  local payload
  if [[ -n "$BASE_URL" ]]; then
    payload="{\"repo\":\"$REPO\",\"service\":\"$SERVICE\",\"commit_id\":\"$COMMIT_ID\",\"base_url\":\"$BASE_URL\"}"
  else
    payload="{\"repo\":\"$REPO\",\"service\":\"$SERVICE\",\"commit_id\":\"$COMMIT_ID\"}"
  fi
  
  # Make request with response body and status code
  local response
  response=$(curl -sS -w "\n%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -X POST "$START_URL" --data "$payload")
  
  # Extract response body and status code
  local response_body
  local status_code
  status_code=$(echo "$response" | tail -n 1)
  response_body=$(echo "$response" | sed '$d')
  
  if [[ "$status_code" =~ ^2 ]]; then
    echo "✅  Quality gate scan started successfully:"
    echo "$response_body"
    
    # Extract scan_id for potential future use using python
    local scan_id
    scan_id=$(echo "$response_body" | python3 -c 'import sys,json;data=json.load(sys.stdin);print(data.get("scan_id", ""))' 2>/dev/null || echo "")
    if [[ -n "$scan_id" ]]; then
      log "Scan ID: $scan_id"
      echo "$scan_id" > scan_id.txt
    fi
  else
    echo "❌  Quality gate scan failed (HTTP $status_code):"
    echo "$response_body"
    exit 1
  fi
}

get_results() {
  # Build JSON payload
  local payload
  if [[ -n "$BASE_URL" ]]; then
    payload="{\"repo\":\"$REPO\",\"service\":\"$SERVICE\",\"commit_id\":\"$COMMIT_ID\",\"base_url\":\"$BASE_URL\"}"
  else
    payload="{\"repo\":\"$REPO\",\"service\":\"$SERVICE\",\"commit_id\":\"$COMMIT_ID\"}"
  fi
  
  # Make request with response body and status code
  local response
  response=$(curl -sS -w "\n%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -X POST "$RESULTS_URL" --data "$payload")
  
  # Extract response body and status code
  local response_body
  local status_code
  status_code=$(echo "$response" | tail -n 1)
  response_body=$(echo "$response" | sed '$d')
  
  if [[ "$status_code" =~ ^2 ]]; then
    # Store response for later use
    echo "$response_body" > results_response.json
    return 0  # Success
  elif [[ "$status_code" == "404" ]]; then
    return 1  # Not found (scan not completed yet)
  else
    echo "❌  Failed to get results (HTTP $status_code):"
    echo "$response_body"
    exit 1
  fi
}

poll_results() {
  log "Polling for quality gate scan results (timeout: ${TIMEOUT}s, interval: ${POLL_INTERVAL}s)"
  
  local start_time
  start_time=$(date +%s)
  
  while true; do
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    
    if [[ $elapsed -ge $TIMEOUT ]]; then
      fail "Timeout reached ($TIMEOUT seconds). Results not available yet."
    fi
    
    log "Checking results (attempt $((elapsed / POLL_INTERVAL + 1)))..."
    
    if get_results; then
      echo "✅  Quality gate scan results:"
      
      local response_body
      response_body=$(cat results_response.json)
      echo "$response_body"
      
      # Check the status and exit code accordingly using python
      local status
      status=$(echo "$response_body" | python3 -c 'import sys,json;data=json.load(sys.stdin);print(data.get("status", ""))' 2>/dev/null || echo "")
      
      case "$status" in
        "COMPLETED")
          local secret_status
          local duplicate_status
          secret_status=$(echo "$response_body" | python3 -c 'import sys,json;data=json.load(sys.stdin);print(data.get("secret_quality_gate", {}).get("status", ""))' 2>/dev/null || echo "")
          duplicate_status=$(echo "$response_body" | python3 -c 'import sys,json;data=json.load(sys.stdin);print(data.get("duplicate_quality_gate", {}).get("status", ""))' 2>/dev/null || echo "")
          
          if [[ "$secret_status" == "FAILED" || "$duplicate_status" == "FAILED" ]]; then
            echo "❌  Quality gate FAILED"
            rm -f results_response.json
            exit 1
          else
            echo "✅  Quality gate PASSED"
            rm -f results_response.json
            exit 0
          fi
          ;;
        "ERROR")
          echo "❌  Quality gate scan encountered an error"
          rm -f results_response.json
          exit 1
          ;;
        "PENDING")
          log "Scan still in progress..."
          ;;
        *)
          log "Unknown status: $status"
          ;;
      esac
      
      # Clean up temp file before continuing loop
      rm -f results_response.json
    fi
    
    log "Results not ready yet, waiting ${POLL_INTERVAL} seconds..."
    sleep "$POLL_INTERVAL"
  done
}

########################################
# 6. Main execution
########################################
case "$OPERATION" in
  "start")
    start_scan
    ;;
  "results")
    poll_results
    ;;
  *)
    fail "Invalid operation: $OPERATION"
    ;;
esac

# Cleanup
rm -f results_response.json scan_id.txt