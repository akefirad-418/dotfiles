#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "requests",
#   "ruamel.yaml",
# ]
# ///

"""
Script to update GitHub tool versions in chezmoidata.yaml to their latest releases.
"""

import sys
import requests
from ruamel.yaml import YAML
from typing import Optional, Tuple


def is_github_repo(repo_url: str) -> bool:
    """Check if the repository URL is a GitHub repository."""
    return repo_url.startswith('https://github.com/')


def extract_github_owner_repo(repo_url: str) -> Optional[Tuple[str, str]]:
    """Extract owner and repository name from GitHub URL."""
    if not is_github_repo(repo_url):
        return None
    
    parts = repo_url.rstrip('/').replace('https://github.com/', '').split('/')
    if len(parts) >= 2:
        return parts[0], parts[1]
    
    return None


def get_latest_github_release(owner: str, repo: str) -> Optional[str]:
    """Get the latest release version from GitHub API."""
    api_url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
    
    try:
        response = requests.get(api_url, timeout=10)
        response.raise_for_status()
        
        release_data = response.json()
        latest_version = release_data.get('tag_name', '')
        return latest_version.lstrip('v')
    
    except requests.RequestException as e:
        print(f"Error fetching latest release for {owner}/{repo}: {e}")
        return None
    except (KeyError, ValueError) as e:
        print(f"Error parsing release data for {owner}/{repo}: {e}")
        return None


def update_versions_in_file(file_path: str, dry_run: bool = False) -> None:
    """Update GitHub tool versions in the YAML file."""
    
    yaml_handler = YAML()
    yaml_handler.indent(mapping=2, sequence=4, offset=2)
    
    try:
        with open(file_path, 'r') as f:
            data = yaml_handler.load(f)
    except Exception as e:
        print(f"Error parsing YAML file: {e}")
        return
    
    if 'tools' not in data:
        print("No 'tools' section found in the file.")
        return
    
    tools = data['tools']
    updates = []
    
    print("Checking for GitHub repositories and their latest versions...")
    print("-" * 60)
    
    for tool_name, tool_data in tools.items():
        repo_url = tool_data.get('repo', '')
        current_version = tool_data.get('version', '')
        
        if not is_github_repo(repo_url):
            print(f"⏭️  {tool_name}: Not a GitHub repository ({repo_url})")
            continue
        
        github_info = extract_github_owner_repo(repo_url)
        if not github_info:
            print(f"❌ {tool_name}: Could not parse GitHub URL ({repo_url})")
            continue
        
        owner, repo = github_info
        latest_version = get_latest_github_release(owner, repo)
        
        if not latest_version:
            print(f"❌ {tool_name}: Could not fetch latest version")
            continue
        
        if latest_version == current_version:
            print(f"✅ {tool_name}: Already up to date ({current_version})")
        else:
            print(f"🔄 {tool_name}: {current_version} → {latest_version}")
            updates.append((tool_name, current_version, latest_version))
    
    print("-" * 60)
    
    if not updates:
        print("No updates needed.")
        return
    
    if dry_run:
        print(f"Would update tool: {updates} (dry run mode)")
        return
    
    for tool_name, _, new_version in updates:
        data['tools'][tool_name]['version'] = new_version
    
    try:
        with open(file_path, 'w') as f:
            yaml_handler.dump(data, f)
        
        print(f"✅ Successfully updated {len(updates)} tools in {file_path}")
        
    except Exception as e:
        print(f"Error writing YAML file: {e}")
        return


def main():
    """Main function."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Update GitHub tool versions in .chezmoidata.yaml"
    )
    parser.add_argument(
        'file',
        nargs='?',
        default='home/.chezmoidata.yaml',
        help='Path to .chezmoidata.yaml file (default: home/.chezmoidata.yaml)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be updated without making changes'
    )
    
    args = parser.parse_args()
    
    try:
        update_versions_in_file(args.file, dry_run=args.dry_run)
    except FileNotFoundError:
        print(f"Error: File '{args.file}' not found.")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main() 