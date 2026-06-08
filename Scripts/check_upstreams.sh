#!/usr/bin/env bash
# Check for new changes in Pete's upstream repository
# Usage: ./Scripts/check_upstreams.sh

set -euo pipefail

UPSTREAM_URL="https://github.com/steipete/CodexBar.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==> Fetching upstream changes...${NC}"
ensure_remote_url() {
    local remote=$1
    local expected_url=$2
    local current_url=""

    if git remote get-url "$remote" >/dev/null 2>&1; then
        current_url=$(git remote get-url "$remote")
        if [ "$current_url" != "$expected_url" ]; then
            echo -e "${YELLOW}Updating $remote remote from $current_url to $expected_url${NC}"
            git remote set-url "$remote" "$expected_url"
        fi
    else
        echo -e "${YELLOW}Adding $remote remote...${NC}"
        git remote add "$remote" "$expected_url"
    fi
    git remote set-url --push "$remote" DISABLED
}

ensure_remote_url upstream "$UPSTREAM_URL"
git fetch upstream --no-tags --prune
git fetch upstream '+refs/tags/v*:refs/tags/upstream/v*' --prune

echo ""

remote_default_branch() {
    local remote=$1
    local branch=""
    local candidate

    branch=$(git symbolic-ref -q --short "refs/remotes/${remote}/HEAD" 2>/dev/null | sed "s#^${remote}/##" || true)
    if [ -z "$branch" ]; then
        branch=$(git remote show "$remote" 2>/dev/null | awk '/HEAD branch/ {print $NF; exit}' || true)
    fi
    if [ -n "$branch" ] && git rev-parse --verify -q "${remote}/${branch}" >/dev/null; then
        echo "$branch"
        return 0
    fi

    for candidate in main master; do
        if git rev-parse --verify -q "${remote}/${candidate}" >/dev/null; then
            echo "$candidate"
            return 0
        fi
    done

    echo -e "${RED}Error: Could not resolve default branch for remote '$remote'.${NC}" >&2
    exit 1
}

echo -e "${BLUE}==> Upstream (steipete/CodexBar) changes:${NC}"
UPSTREAM_BRANCH=$(remote_default_branch upstream)
UPSTREAM_REF="upstream/${UPSTREAM_BRANCH}"
UPSTREAM_VERSION=$(awk -F= '$1 == "UPSTREAM_VERSION" {print $2; exit}' version.env)
UPSTREAM_BASE_REF="upstream/${UPSTREAM_VERSION}"
if [ -z "$UPSTREAM_VERSION" ] || ! git rev-parse --verify -q "$UPSTREAM_BASE_REF" >/dev/null; then
    echo -e "${RED}Error: Could not resolve UPSTREAM_VERSION=${UPSTREAM_VERSION:-<unset>} from version.env.${NC}" >&2
    exit 1
fi

UPSTREAM_COUNT=$(git log --oneline "${UPSTREAM_BASE_REF}..${UPSTREAM_REF}" --no-merges 2>/dev/null | wc -l | tr -d ' ')

if [ "$UPSTREAM_COUNT" -gt 0 ]; then
    echo -e "${GREEN}Found $UPSTREAM_COUNT new commits since $UPSTREAM_VERSION${NC}"
    echo ""
    git log --oneline --graph "${UPSTREAM_BASE_REF}..${UPSTREAM_REF}" --no-merges | head -20 || true
    echo ""
    echo -e "${YELLOW}Files changed:${NC}"
    git diff --stat "${UPSTREAM_BASE_REF}..${UPSTREAM_REF}" | tail -20 || true
else
    echo -e "${GREEN}No new commits since $UPSTREAM_VERSION${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}==> Summary${NC}"
echo "Upstream commits since $UPSTREAM_VERSION: $UPSTREAM_COUNT"

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  Review upstream: ./Scripts/review_upstream.sh upstream"
echo "  Detailed diff:   git diff upstream/$UPSTREAM_VERSION..upstream/$UPSTREAM_BRANCH"
