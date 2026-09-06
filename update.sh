#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

repo="anomalyco/opencode"
flake="flake.nix"

if [ $# -ge 1 ]; then
  version="${1#v}"
else
  version="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")"
  version="${version##*/tag/v}"
fi

if [ -z "$version" ]; then
  echo "could not determine version" >&2
  exit 1
fi

current="$(sed -n 's/^      version = "\(.*\)";$/\1/p' "$flake")"

if [ "$version" = "$current" ]; then
  echo "already at $version"
  exit 0
fi

echo "updating $current -> $version"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

sed "s/^      version = \".*\";$/      version = \"$version\";/" "$flake" > "$tmp/flake.nix"

for asset in $(sed -n 's/^ *asset = "\(.*\)";$/\1/p' "$flake"); do
  url="https://github.com/$repo/releases/download/v$version/$asset"
  echo "fetching $url"
  curl -fsSL -o "$tmp/$asset" "$url"
  hash="sha256-$(openssl dgst -sha256 -binary "$tmp/$asset" | base64)"
  echo "$asset $hash"
  sed "/asset = \"$asset\";/{n;s|hash = \".*\";|hash = \"$hash\";|;}" "$tmp/flake.nix" > "$tmp/flake.nix.new"
  mv "$tmp/flake.nix.new" "$tmp/flake.nix"
done

mv "$tmp/flake.nix" "$flake"
echo "updated to $version"
