#!/bin/bash
# Shared release/download helpers for the Omarchy AppImage commands.
# Sourced by omarchy-install-appimage-github, omarchy-install-appimage-url, and
# omarchy-update-appimages.

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

# Newest usable release. Stable tracking takes the published "latest" release and
# falls back to the newest prerelease only when the project ships nothing else,
# which is how continuous/nightly AppImage projects ship. Prerelease tracking
# (second argument 1) takes whichever non-draft release was published last.
latest_release_json() {
  local repo="$1" prerelease="${2:-0}" json
  if ((prerelease == 0)); then
    json=$(gh_api "repos/$repo/releases/latest")
    if [[ -n $json ]] && jq -e '.tag_name' <<<"$json" &>/dev/null; then
      printf '%s' "$json"
      return 0
    fi
  fi
  json=$(gh_api "repos/$repo/releases?per_page=20")
  jq -e '[.[] | select(.draft | not)] | sort_by(.published_at) | last | select(. != null)' <<<"$json" 2>/dev/null
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

# Probe a direct download URL without fetching the image. Prints
# "file-name<TAB>stamp". The stamp is the strongest change validator the final
# response offers — ETag, then Last-Modified, then size — so a new build behind
# the same URL is noticed. An empty stamp means the server exposes nothing to
# compare and the URL cannot be tracked. HEAD comes first; servers that refuse it
# (signed S3/CDN redirects often do) get a one-byte ranged GET instead.
url_probe() {
  local url="$1" headers
  headers=$(curl -fsSIL --max-time 20 -w 'x-effective-url: %{url_effective}\n' "$url" 2>/dev/null) ||
    headers=$(curl -fsSL --max-time 20 -r 0-0 -o /dev/null -D - \
      -w 'x-effective-url: %{url_effective}\n' "$url" 2>/dev/null) ||
    return 1

  tr -d '\r' <<<"$headers" | awk -v url="$url" '
    function base(u) { sub(/[?#].*/, "", u); sub(/.*\//, "", u); return u }
    function appimage(n) { return tolower(n) ~ /\.appimage$/ }
    # Every redirect hop starts a new header block; only the last one counts.
    /^HTTP\// { etag = modified = size = total = disposition = ""; next }
    {
      i = index($0, ":")
      if (!i) next
      key = tolower(substr($0, 1, i - 1))
      value = substr($0, i + 1)
      sub(/^[ \t]+/, "", value); sub(/[ \t]+$/, "", value)
    }
    key == "etag" { etag = value }
    key == "last-modified" { modified = value }
    key == "content-length" { size = value }
    key == "content-range" && value ~ /\/[0-9]+$/ { total = value; sub(/.*\//, "", total) }
    key == "content-disposition" { disposition = value }
    key == "x-effective-url" { effective = value }
    END {
      name = ""
      if (match(disposition, /filename\*=[^;]+/)) {
        name = substr(disposition, RSTART + 10, RLENGTH - 10)
        sub(/^[^\047]*\047[^\047]*\047/, "", name)
      } else if (match(disposition, /filename=("[^"]*"|[^;]+)/)) {
        name = substr(disposition, RSTART + 9, RLENGTH - 9)
        gsub(/"/, "", name)
      }
      if (!appimage(name)) {
        if (appimage(base(effective))) name = base(effective)
        else if (appimage(base(url))) name = base(url)
        else {
          if (name == "") name = base(url)
          if (name == "") name = "download"
          name = name ".AppImage"
        }
      }
      gsub(/\//, "_", name)

      if (total != "") size = total
      stamp = ""
      if (etag != "") stamp = "etag:" etag
      else if (modified != "") stamp = "modified:" modified
      else if (size != "" && size != "0") stamp = "size:" size
      printf "%s\t%s\n", name, stamp
    }
  '
}
