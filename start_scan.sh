#!/bin/bash
# CodeAnt Analysis Runner - Inline Python Script
# Usage: ./start_scan.sh -a <access_token> -r <repo_name> -c <commit_id> -s <service> [-b <branch>] [-i <include>] [-e <exclude>] [-p <polling_interval>] [-t <timeout>] [-n] [-u <base_url>]

set -e

# Default values
POLLING_INTERVAL=30
TIMEOUT=300
NO_WAIT=false
BASE_URL=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--access-token)
      ACCESS_TOKEN="$2"
      shift 2
      ;;
    -r|--repo)
      REPO_NAME="$2"
      shift 2
      ;;
    -c|--commit-id)
      COMMIT_ID="$2"
      shift 2
      ;;
    -s|--service)
      SERVICE="$2"
      shift 2
      ;;
    -b|--branch)
      BRANCH="$2"
      shift 2
      ;;
    -i|--include-files)
      INCLUDE_FILES="$2"
      shift 2
      ;;
    -e|--exclude-files)
      EXCLUDE_FILES="$2"
      shift 2
      ;;
    -p|--polling-interval)
      POLLING_INTERVAL="$2"
      shift 2
      ;;
    -t|--timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    -n|--no-wait)
      NO_WAIT=true
      shift
      ;;
    -u|--base-url)
      BASE_URL="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 -a <access_token> -r <repo_name> -c <commit_id> -s <service> [options]"
      echo "Options:"
      echo "  -a, --access-token    Access token for authentication (required)"
      echo "  -r, --repo            Repository name in format org/repo (required)"
      echo "  -c, --commit-id       Commit ID to analyze (required)"
      echo "  -s, --service         Service type (github/gitlab/azuredevops) (required)"
      echo "  -b, --branch          Branch name (optional)"
      echo "  -i, --include-files   Files to include (optional)"
      echo "  -e, --exclude-files   Files to exclude (optional)"
      echo "  -p, --polling-interval  Polling interval in seconds (default: 30)"
      echo "  -t, --timeout         Timeout in seconds (default: 300)"
      echo "  -n, --no-wait         Skip waiting for results, only trigger the scan"
      echo "  -u, --base-url        Custom base URL for git provider (optional)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "❌ Error: access token is required (-a)"
    exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
    echo "❌ Error: repository name is required (-r)"
    exit 1
fi

if [[ -z "$COMMIT_ID" ]]; then
    echo "❌ Error: commit ID is required (-c)"
    exit 1
fi

if [[ -z "$SERVICE" ]]; then
    echo "❌ Error: service is required (-s)"
    exit 1
fi

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: python3 is required but not installed"
    exit 1
fi

# Run the inline Python script with parsed arguments
python3 - "$REPO_NAME" "$SERVICE" "$COMMIT_ID" "$ACCESS_TOKEN" "$POLLING_INTERVAL" "$TIMEOUT" "${BRANCH:-}" "${INCLUDE_FILES:-}" "${EXCLUDE_FILES:-}" "$NO_WAIT" "${BASE_URL:-}" << 'EOF'
#!/usr/bin/env python3

import sys
import json
import time
import urllib.request
import urllib.parse
import urllib.error
from typing import Dict, Any, Optional, Tuple


class CodeAntAnalyzer:
    def __init__(self, base_url: str = "https://api.codeant.ai",
                 service: str = "github", custom_service_url: str = ""):
        self.base_url = base_url
        self.start_scan_url = f"{base_url}/api/analysis/start"
        self.security_results_url = f"{base_url}/api/analysis/results"
        self.sca_results_url = f"{base_url}/api/analysis/results/sca"
        
        # Set service-specific base URLs
        if custom_service_url:
            # Use custom URL if provided
            if service == "gitlab":
                self.gitlab_base_url = custom_service_url
            elif service == "azuredevops":
                self.azure_devops_base_url = custom_service_url
            elif service == "github":
                self.github_base_url = custom_service_url
        else:
            # Use defaults
            self.gitlab_base_url = "https://gitlab.com"
            self.azure_devops_base_url = "https://dev.azure.com"
            self.github_base_url = "https://github.com"
        
    def start_scan(self, repo: str, service: str, commit_id: str, access_token: str,
                   branch: str = "", include_files: str = "", exclude_files: str = "") -> Dict[str, Any]:
        """Start analysis scan"""
        payload = {
            "repo": repo,
            "service": service,
            "commit_id": commit_id,
            "access_token": access_token,
            "include_files": include_files,
            "exclude_files": exclude_files,
            "branch": branch
        }
        
        # Add service-specific base URLs to payload
        if service == "gitlab":
            payload["gitlab_base_url"] = self.gitlab_base_url
        elif service == "azuredevops":
            payload["azure_devops_base_url"] = self.azure_devops_base_url
        elif service == "github":
            payload["github_base_url"] = self.github_base_url
        
        try:
            data = json.dumps(payload).encode('utf-8')
            req = urllib.request.Request(
                self.start_scan_url,
                data=data,
                headers={"Content-Type": "application/json"}
            )
            
            response = urllib.request.urlopen(req)
            status_code = response.getcode()
            response_text = response.read().decode('utf-8')
            
            if status_code >= 200 and status_code < 300:
                return {
                    "success": True,
                    "data": json.loads(response_text),
                    "status_code": status_code
                }
            else:
                return {
                    "success": False,
                    "error": f"HTTP {status_code}: {response_text}",
                    "status_code": status_code
                }
        except urllib.error.HTTPError as e:
            return {
                "success": False,
                "error": f"HTTP {e.code}: {e.read().decode('utf-8')}",
                "status_code": e.code
            }
        except Exception as e:
            return {
                "success": False,
                "error": f"Request failed: {str(e)}",
                "status_code": 0
            }
    
    def build_results_payload(self, repo: str, service: str, commit_id: str, access_token: str) -> Dict[str, Any]:
        """Build payload for results requests"""
        payload = {
            "repo": repo,
            "service": service,
            "commit_id": commit_id,
            "access_token": access_token
        }
        
        # Add service-specific base URLs from instance
        if service == "gitlab":
            payload["gitlab_base_url"] = self.gitlab_base_url
        elif service == "azuredevops":
            payload["azure_devops_base_url"] = self.azure_devops_base_url
        elif service == "github":
            payload["github_base_url"] = self.github_base_url
            
        return payload
    
    def fetch_security_results(self, repo: str, service: str, commit_id: str, access_token: str) -> Tuple[bool, Optional[Dict[str, Any]], bool]:
        """Fetch security analysis results
        
        Returns:
            (success, data, is_pending)
        """
        payload = self.build_results_payload(repo, service, commit_id, access_token)
        
        try:
            data = json.dumps(payload).encode('utf-8')
            req = urllib.request.Request(
                self.security_results_url,
                data=data,
                headers={"Content-Type": "application/json"}
            )
            
            response = urllib.request.urlopen(req)
            status_code = response.getcode()
            response_text = response.read().decode('utf-8')
            
            if status_code >= 200 and status_code < 300:
                data = json.loads(response_text)
                is_pending = data.get("status") == "pending"
                return True, data, is_pending
            elif status_code in [404, 204]:
                return False, None, False  # Results not ready yet
            else:
                return False, None, False
                
        except urllib.error.HTTPError as e:
            if e.code == 401:
                raise Exception("Authentication failed. Please check your access token.")
            elif e.code in [404, 204]:
                return False, None, False  # Results not ready yet
            else:
                print(f"Error fetching security results: HTTP {e.code}")
                return False, None, False
        except Exception as e:
            print(f"Error fetching security results: {e}")
            return False, None, False
    
    def fetch_sca_results(self, repo: str, service: str, commit_id: str, access_token: str) -> Tuple[bool, Optional[Dict[str, Any]], bool]:
        """Fetch SCA analysis results
        
        Returns:
            (success, data, is_pending)
        """
        payload = self.build_results_payload(repo, service, commit_id, access_token)
        
        try:
            data = json.dumps(payload).encode('utf-8')
            req = urllib.request.Request(
                self.sca_results_url,
                data=data,
                headers={"Content-Type": "application/json"}
            )
            
            response = urllib.request.urlopen(req)
            status_code = response.getcode()
            response_text = response.read().decode('utf-8')
            
            if status_code >= 200 and status_code < 300:
                data = json.loads(response_text)
                is_pending = data.get("status") == "pending"
                return True, data, is_pending
            elif status_code in [404, 204]:
                return False, None, False  # Results not ready yet
            else:
                return False, None, False
                
        except urllib.error.HTTPError as e:
            if e.code == 401:
                raise Exception("Authentication failed. Please check your access token.")
            elif e.code in [404, 204]:
                return False, None, False  # Results not ready yet
            else:
                print(f"Error fetching SCA results: HTTP {e.code}")
                return False, None, False
        except Exception as e:
            print(f"Error fetching SCA results: {e}")
            return False, None, False
    
    def extract_security_issues(self, data: Dict[str, Any]) -> list:
        """Extract security issues from response data"""
        if isinstance(data, list):
            return data
        elif isinstance(data, dict):
            if "issues" in data and isinstance(data["issues"], list):
                return data["issues"]
            elif "results" in data:
                results = data["results"]
                if isinstance(results, list):
                    return results
                elif isinstance(results, dict):
                    # Flatten all values that are lists
                    issues = []
                    for value in results.values():
                        if isinstance(value, list):
                            issues.extend(value)
                        elif isinstance(value, dict):
                            issues.append(value)
                    return issues
        return []
    
    def extract_sca_vulnerabilities(self, data: Dict[str, Any]) -> list:
        """Extract SCA vulnerabilities from response data"""
        if isinstance(data, list):
            return data
        elif isinstance(data, dict):
            if "vulnerabilities" in data and isinstance(data["vulnerabilities"], list):
                return data["vulnerabilities"]
            elif "results" in data:
                results = data["results"]
                if isinstance(results, dict) and "vulnerabilities" in results:
                    return results["vulnerabilities"]
                elif isinstance(results, list):
                    return results
        return []
    
    def poll_for_results(self, repo: str, service: str, commit_id: str, access_token: str,
                        poll_interval: int, timeout: int) -> Dict[str, Any]:
        """Poll for analysis results"""
        start_time = time.time()
        security_found = False
        sca_found = False
        security_data = None
        sca_data = None
        attempt = 0
        
        print(f"📝 Polling for analysis results")
        print(f"📝 Repository: {repo}")
        print(f"📝 Commit: {commit_id}")
        print(f"📝 Service: {service}")
        print(f"📝 Timeout: {timeout}s, Poll interval: {poll_interval}s")
        
        while True:
            current_time = time.time()
            elapsed = current_time - start_time
            
            if elapsed >= timeout:
                print(f"⚠️ Timeout reached ({timeout} seconds)")
                if not security_found and not sca_found:
                    return {
                        "success": False,
                        "error": "No results were available within the timeout period",
                        "security_issues": [],
                        "sca_vulnerabilities": []
                    }
                else:
                    print("📝 Partial results obtained before timeout")
                    break
            
            attempt += 1
            print(f"📝 Polling attempt #{attempt} ({int(elapsed)}s elapsed)...")
            
            # Try to fetch security results if not already found
            if not security_found:
                success, data, is_pending = self.fetch_security_results(repo, service, commit_id, access_token)
                
                if success:
                    if not is_pending:
                        print("✅ Security analysis results retrieved")
                        security_found = True
                    else:
                        print("📝 Security results pending - saving partial data")
                    security_data = data
                else:
                    print("📝 Security results not ready yet")
            
            # Try to fetch SCA results if not already found
            if not sca_found:
                success, data, is_pending = self.fetch_sca_results(repo, service, commit_id, access_token)
                
                if success and not is_pending:
                    print("✅ SCA analysis results retrieved")
                    sca_found = True
                    sca_data = data
                else:
                    print("📝 SCA results not ready yet")
            
            # Check if both results are found
            if security_found and sca_found:
                print("✅ All analysis results retrieved successfully!")
                break
            
            print(f"📝 Waiting {poll_interval} seconds before next attempt...")
            time.sleep(poll_interval)
        
        # Extract issues and vulnerabilities
        security_issues = self.extract_security_issues(security_data) if security_data else []
        sca_vulnerabilities = self.extract_sca_vulnerabilities(sca_data) if sca_data else []
        
        return {
            "success": True,
            "security_issues": security_issues,
            "sca_vulnerabilities": sca_vulnerabilities,
            "security_found": security_found,
            "sca_found": sca_found,
            "raw_security_data": security_data,
            "raw_sca_data": sca_data
        }


def main():
    if len(sys.argv) != 12:
        print("Usage: python script.py <repo_name> <service> <commit_id> <access_token> <polling_interval> <timeout> <branch> <include_files> <exclude_files> <no_wait> <base_url>")
        print("Example: python script.py org/repo github abc123def456 ghp_token123 30 300 main '' '' false ''")
        sys.exit(1)
    
    repo_name = sys.argv[1]
    service = sys.argv[2]
    commit_id = sys.argv[3]
    access_token = sys.argv[4]
    
    try:
        polling_interval = int(sys.argv[5])
        timeout = int(sys.argv[6])
    except ValueError:
        print("❌ Error: polling_interval and timeout must be integers")
        sys.exit(1)
    
    branch = sys.argv[7] if len(sys.argv) > 7 else ""
    include_files = sys.argv[8] if len(sys.argv) > 8 else ""
    exclude_files = sys.argv[9] if len(sys.argv) > 9 else ""
    no_wait = sys.argv[10].lower() == "true" if len(sys.argv) > 10 else False
    custom_base_url = sys.argv[11] if len(sys.argv) > 11 else ""
    
    # Validate parameters
    if not repo_name or not service or not commit_id or not access_token:
        print("❌ Error: All parameters are required")
        sys.exit(1)
    
    if polling_interval < 1 or timeout < 1:
        print("❌ Error: polling_interval and timeout must be positive integers")
        sys.exit(1)
    
    # Initialize analyzer with service and custom base URL
    analyzer = CodeAntAnalyzer(service=service, custom_service_url=custom_base_url)
    
    # Step 1: Start scan
    print("🚀 Starting analysis scan...")
    start_result = analyzer.start_scan(repo_name, service, commit_id, access_token, branch, include_files, exclude_files)
    
    if not start_result["success"]:
        print(f"❌ Failed to start analysis scan: {start_result['error']}")
        sys.exit(1)
    
    print("✅ Analysis scan started successfully")
    
    # Check if we should skip waiting for results
    if no_wait:
        print("\n✅ Scan triggered successfully (--no-wait flag set)")
        print("📝 Skipping result polling as requested")
        result = {
            "repository": repo_name,
            "service": service,
            "commit_id": commit_id,
            "status": "triggered",
            "message": "Scan triggered successfully. Results will be available later.",
            "scan_response": start_result["data"]
        }
        print("\n🎯 Scan Trigger Result (JSON):")
        print("=" * 40)
        print(json.dumps(result, indent=2))
        
        # write results in results.json file
        with open("results.json", "w") as f:
            json.dump(result, f, indent=2)
        
        sys.exit(0)
    
    # Step 2: Poll for results
    print("\n⏳ Polling for analysis results...")
    poll_result = analyzer.poll_for_results(repo_name, service, commit_id, access_token, polling_interval, timeout)
    
    if not poll_result["success"]:
        print(f"❌ Failed to get results: {poll_result['error']}")
        result = {
            "repository": repo_name,
            "service": service,
            "commit_id": commit_id,
            "status": "failed",
            "error": poll_result['error'],
            "security_issues": [],
            "sca_vulnerabilities": []
        }
    else:
        # Step 3: Format final results
        print("\n📊 Analysis Results Summary")
        print("=" * 40)
        print(f"Repository: {repo_name}")
        print(f"Commit: {commit_id}")
        print(f"Service: {service}")
        print(f"Security issues: {len(poll_result['security_issues'])}")
        print(f"SCA vulnerabilities: {len(poll_result['sca_vulnerabilities'])}")
        
        status = "success"
        if not poll_result["security_found"] or not poll_result["sca_found"]:
            status = "partial"
        
        result = {
            "repository": repo_name,
            "service": service,
            "commit_id": commit_id,
            "status": status,
            "security_issues_count": len(poll_result['security_issues']),
            "sca_vulnerabilities_count": len(poll_result['sca_vulnerabilities']),
            "security_issues": poll_result['security_issues'],
            "sca_vulnerabilities": poll_result['sca_vulnerabilities'],
            "security_found": poll_result["security_found"],
            "sca_found": poll_result["sca_found"]
        }
    
    # Step 4: Output results in JSON format
    print("\n🎯 Final Results (JSON):")
    print("=" * 40)
    print(json.dumps(result, indent=2))

    # write results in results.json file
    with open("results.json", "w") as f:
        json.dump(result, f, indent=2)
    
    # Exit with appropriate code
    if result["status"] == "failed":
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
EOF
