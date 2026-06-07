#!/usr/bin/env bash
set -euo pipefail

# release.sh — two-phase Sparkle release orchestration.
#
# Phase 1 (default): build + sign + notarize + create DRAFT GitHub release
#                    with uploaded assets, then stop.
#     Usage: ./Scripts/release.sh
#
# Phase 2 (--finalize): publish the existing draft, generate + sign the
#                       appcast entry, commit + push appcast.xml, verify.
#     Usage: ./Scripts/release.sh --finalize
#
# The draft gate between phases is the human-review checkpoint. Once you
# finalize, the release is live and Sparkle clients will start seeing it
# on their next check-for-updates cycle.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
if [[ -f "$ROOT/.mac-release.env" ]]; then
  source "$ROOT/.mac-release.env"
fi
source "$ROOT/Scripts/load-release-secrets.sh"
source "$ROOT/Scripts/sparkle_helpers.sh"

APPCAST="$ROOT/appcast.xml"
APP_NAME="${MAC_RELEASE_APP_NAME:-QuotaKit}"
RELEASE_REPO="${MAC_RELEASE_REPO:-ColumbusLabs/QuotaKit}"
RELEASE_ASSET_BASENAME="${APP_NAME}-macos-universal-${MARKETING_VERSION}"
ARTIFACT_PREFIX="${APP_NAME}-macos-"
BUNDLE_ID="${MAC_RELEASE_BUNDLE_ID:-com.columbuslabs.quotakit.mac}"
RELEASE_BRANCH="${QUOTAKIT_RELEASE_BRANCH:-main}"
FEED_URL="https://raw.githubusercontent.com/${RELEASE_REPO}/${RELEASE_BRANCH}/appcast.xml"
TAG="v${MARKETING_VERSION}"
RELEASE_TITLE="${APP_NAME} ${MARKETING_VERSION} Mobile ${MOBILE_VERSION}"

phase1() {
  require_clean_worktree
  ensure_changelog_finalized "$MARKETING_VERSION"
  ensure_appcast_monotonic "$APPCAST" "$MARKETING_VERSION" "$BUILD_NUMBER"

  "$ROOT/Scripts/lint.sh" lint

  # `swift test` is authoritatively gated by CI on every push to
  # mobile-dev; re-running it here is belt-and-suspenders. Some tests
  # (Claude OAuth delegated-refresh, credential prompts) block on real
  # keychain on a developer Mac and hang indefinitely, unlike the
  # sandboxed CI environment where they run to completion. Opt in via
  # RUN_SWIFT_TEST=1 on machines where it works.
  if [[ "${RUN_SWIFT_TEST:-0}" == "1" ]]; then
    swift test
  else
    echo "Skipping swift test locally (CI gates it on every push; set RUN_SWIFT_TEST=1 to run)."
  fi

  if [[ -f "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" \
     && -f "${ROOT}/${RELEASE_ASSET_BASENAME}.dSYM.zip" ]]; then
    echo "Reusing existing notarized artifacts (delete them to force a fresh build):"
    ls -lh "${RELEASE_ASSET_BASENAME}.zip" "${RELEASE_ASSET_BASENAME}.dSYM.zip"
  else
    "$ROOT/Scripts/sign-and-notarize.sh"
  fi

  local KEY_FILE NOTES_FILE
  KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
  NOTES_FILE=$(mktemp /tmp/quotakit-notes.XXXXXX)
  # Eager-expand paths into the trap so the cleanup still works after
  # phase1's local scope is gone (set -u would otherwise fail on unbound
  # $KEY_FILE / $NOTES_FILE when the EXIT trap fires post-return).
  trap "rm -f '$KEY_FILE' '$NOTES_FILE'" EXIT

  probe_sparkle_key "$KEY_FILE"
  extract_notes_from_changelog "$MARKETING_VERSION" "$NOTES_FILE"

  git tag -a -f -m "${RELEASE_TITLE}" "$TAG"
  git push -f origin "$TAG"

  # gh allows multiple drafts for the same logical tag (the tag doesn't
  # actually materialize on GitHub until the draft is published), so a
  # previous failed phase 1 can leave an orphan draft that sits next to
  # any fresh one we create. Sweep those out before creating the new draft.
  orphan_ids=$(gh api "repos/${RELEASE_REPO}/releases" \
    --jq ".[] | select(.tag_name == \"$TAG\" and .draft == true) | .id" 2>/dev/null || true)
  for id in $orphan_ids; do
    echo "Cleaning up orphan draft id=$id for $TAG (from a previous phase 1 run)."
    gh api -X DELETE "repos/${RELEASE_REPO}/releases/$id" >/dev/null
  done

  # Pin --repo explicitly so gh never picks the inherited upstream remote.
  gh release create "$TAG" \
    "${RELEASE_ASSET_BASENAME}.zip" "${RELEASE_ASSET_BASENAME}.dSYM.zip" \
    --repo "$RELEASE_REPO" \
    --draft \
    --title "${RELEASE_TITLE}" \
    --notes-file "$NOTES_FILE"

  local draft_url
  draft_url=$(gh release view "$TAG" --repo "$RELEASE_REPO" --json url -q .url)

  cat <<EOF

============================================================
Phase 1 complete — DRAFT release is staged (not public yet).

  Tag:        $TAG
  Review at:  $draft_url

What to verify in the GitHub UI:
  - Title and release notes render correctly
  - ${RELEASE_ASSET_BASENAME}.zip is present (expect ~10-50 MB)
  - ${RELEASE_ASSET_BASENAME}.dSYM.zip is present
  - Tag matches: $TAG

When ready to publish + push appcast:
  ./Scripts/release.sh --finalize

To abort and clean up:
  gh release delete $TAG --yes
  git push origin :$TAG
============================================================
EOF
}

phase2() {
  if [[ ! -f "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" ]]; then
    err "Release zip not found at ${RELEASE_ASSET_BASENAME}.zip. Did phase 1 run?"
  fi

  local is_draft
  if ! is_draft=$(gh release view "$TAG" --repo "$RELEASE_REPO" --json isDraft -q .isDraft 2>&1); then
    err "No release found for tag $TAG. Run phase 1 first (./Scripts/release.sh)."
  fi
  if [[ "$is_draft" == "true" ]]; then
    echo "Publishing draft release $TAG..."
    gh release edit "$TAG" --repo "$RELEASE_REPO" --draft=false
  else
    echo "Release $TAG is already published; proceeding to appcast generation."
  fi

  local KEY_FILE
  KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
  trap "rm -f '$KEY_FILE'" EXIT

  clear_sparkle_caches "$BUNDLE_ID"

  SPARKLE_PRIVATE_KEY_FILE="$KEY_FILE" \
    SPARKLE_RELEASE_VERSION="$MARKETING_VERSION" \
    SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/${RELEASE_REPO}/releases/download/${TAG}/" \
    "$ROOT/Scripts/make_appcast.sh" \
    "${RELEASE_ASSET_BASENAME}.zip" \
    "$FEED_URL"

  verify_appcast_entry "$APPCAST" "$MARKETING_VERSION" "$KEY_FILE"

  git add "$APPCAST"
  git commit -m "docs: update appcast for ${MARKETING_VERSION}"
  git push origin "$RELEASE_BRANCH"

  if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
    local PREV_TAG
    PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
    [[ -z "$PREV_TAG" ]] && err "RUN_SPARKLE_UPDATE_TEST=1 but no previous tag found"
    "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "$TAG"
  fi

  QUOTAKIT_RELEASE_REPO="$RELEASE_REPO" check_assets "$TAG" "$ARTIFACT_PREFIX"
  # Note: the release tag was already pushed in phase 1
  # (git push -f origin "$TAG"). Running `git push origin --tags` here
  # tries to push ALL local tags — including the upstream tag namespace
  # inherited via `remote add upstream` — which hits conflicts on any
  # old tag origin doesn't have in the same shape. Skip it.

  cat <<EOF

============================================================
Phase 2 complete — Release ${MARKETING_VERSION} is LIVE.

  Release:    https://github.com/${RELEASE_REPO}/releases/tag/$TAG
  Appcast:    $FEED_URL
  CFBundle:   ${BUILD_NUMBER}.${MOBILE_VERSION}

Sparkle clients will prompt upgrade on their next check-for-updates
cycle (raw.githubusercontent.com cache may take a few minutes to
propagate).
============================================================
EOF
}

case "${1:-phase1}" in
  phase1|--phase1|"")
    phase1
    ;;
  phase2|--phase2|--finalize)
    phase2
    ;;
  *)
    err "Usage: $0 [--finalize]"
    ;;
esac
