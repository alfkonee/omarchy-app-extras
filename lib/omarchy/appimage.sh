#!/bin/bash
# Shared GitHub-release helpers for the Omarchy AppImage commands.
# Sourced by omarchy-install-appimage-github and omarchy-update-appimages.

APPIMAGE_GH_AUTH=""

gh_available() {
  [[ -n $APPIMAGE_GH_AUTH ]] && return "$APPIMAGE_GH_AUTH"
  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    APPIMAGE_GH_AUTH=0
  else
    APPIMAGE_GH_AUTH=1
  fi
  return "$APPIMAGE_GH_AUTH"
}

# GitHub REST call. gh carries the user's token (5000 req/h) when it is set up;
# anonymous curl is the fallback and is enough for the occasional check.
gh_api() {
  local path="$1"
  if gh_available; then
    gh api -H "Accept: application/vnd.github+json" "$path" 2>/dev/null
  else
    curl -fsSL --max-time 20 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/$path" 2>/dev/null
  fi
}

# Accepts owner/repo, a github.com URL, or a releases page URL.
normalize_repo() {
  local input="$1"
  input=${input#https://}
  input=${input#http://}
  input=${input#github.com/}
  input=${input%.git}
  # Strip anything past owner/repo (releases, tree/main, ...).
  awk -F/ 'NF >= 2 { print $1 "/" $2 }' <<<"$input"
}

# Newest usable release: the published one if there is any, otherwise the newest
# prerelease, which is how continuous/nightly AppImage projects ship.
latest_release_json() {
  local repo="$1" json
  json=$(gh_api "repos/$repo/releases/latest")
  if [[ -n $json ]] && jq -e '.tag_name' <<<"$json" &>/dev/null; then
    printf '%s' "$json"
    return 0
  fi
  json=$(gh_api "repos/$repo/releases?per_page=10")
  jq -e '[.[] | select(.draft | not)] | first | select(. != null)' <<<"$json" 2>/dev/null
}

# AppImage assets as "name<TAB>url" rows, x86_64/amd64 ones first.
release_appimage_assets() {
  jq -r '
    [.assets[] | select(.name | test("\\.appimage$"; "i"))]
    | sort_by((.name | test("(x86_64|amd64)"; "i")) | not)
    | .[] | "\(.name)\t\(.browser_download_url)"
  ' 2>/dev/null
}

# Turn an asset name into a version-agnostic glob so the next release's asset is
# still recognisable: Foo-1.2.3-x86_64.AppImage -> Foo-*-x86_64.AppImage
asset_glob() {
  local name="$1"
  sed -E 's/[0-9]+(\.[0-9]+)+/*/g; s/\*[-_.]?\*/*/g' <<<"$name"
}

download_asset() {
  local url="$1" dest="$2"
  curl -fL --retry 2 --progress-bar -o "$dest" "$url"
}
