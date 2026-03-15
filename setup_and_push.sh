#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is not set. Export it in your shell before running this script."
  exit 1
fi

REPO_NAME="${REPO_NAME:-$(basename "$PWD")}"
REPO_PRIVATE="${REPO_PRIVATE:-1}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is not installed."
  exit 1
fi

if [[ ! -d ".git" ]]; then
  git init
fi

if git rev-parse --verify HEAD >/dev/null 2>&1; then
  :
else
  git add -A
  git commit -m "Initial commit" >/dev/null 2>&1 || true
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "No commits exist yet. Configure git user.name and user.email, then rerun:"
  echo "  git config --global user.name \"Your Name\""
  echo "  git config --global user.email \"you@example.com\""
  exit 1
fi

default_branch="$(git symbolic-ref --short -q HEAD || true)"
if [[ -z "$default_branch" ]]; then
  git checkout -B main >/dev/null 2>&1 || git checkout -b main >/dev/null 2>&1
else
  git branch -M "$default_branch" main >/dev/null 2>&1 || true
fi

owner="$(
  curl -sS \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/user | python3 -c 'import json,sys; print(json.load(sys.stdin).get("login",""))'
)"

if [[ -z "$owner" ]]; then
  echo "Unable to determine GitHub user from GITHUB_TOKEN."
  exit 1
fi

create_repo_payload="$(
  python3 - <<PY
import json, os
repo_name = os.environ.get("REPO_NAME")
private = os.environ.get("REPO_PRIVATE", "1") not in ("0", "false", "False", "no", "NO")
print(json.dumps({"name": repo_name, "private": private}))
PY
)"

curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  -d "$create_repo_payload" \
  https://api.github.com/user/repos >/dev/null 2>&1 || true

remote_url="https://github.com/${owner}/${REPO_NAME}.git"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$remote_url"
else
  git remote add origin "$remote_url"
fi

basic_auth="$(
  printf "x-access-token:%s" "${GITHUB_TOKEN}" | base64
)"

if git -c http.extraHeader="AUTHORIZATION: basic ${basic_auth}" fetch origin main >/dev/null 2>&1; then
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    if ! git merge --allow-unrelated-histories --no-edit origin/main >/dev/null 2>&1; then
      echo "Remote 'main' has commits that conflict with your local history."
      echo "Resolve the merge conflicts, commit, then rerun:"
      echo "  git push -u origin main"
      exit 1
    fi
  fi
fi

git -c http.extraHeader="AUTHORIZATION: basic ${basic_auth}" push -u origin main
