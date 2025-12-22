#!/usr/bin/env bash

set -exuo pipefail

# Ensure CONFIGURE_NIX_SUBSTITUTER is set
if [ -z "$CONFIGURE_NIX_SUBSTITUTER" ]; then
  echo >&2 "Aborting: 'CONFIGURE_NIX_SUBSTITUTER' environment variable is not set.";
  exit 1;
fi

# Restore Nix substituter credentials if available
if [ -n "${NIX_AWS_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="${NIX_AWS_ACCESS_KEY_ID}"
  export AWS_SECRET_ACCESS_KEY="${NIX_AWS_SECRET_ACCESS_KEY}"
fi

# Allow pushing to fail.

# copy the outputs of drv-paths
# https://www.haskellforall.com/2022/10/how-to-correctly-cache-build-time.html

if [ -f /tmp/drv-paths ]; then
  cat /tmp/drv-paths | xargs nix-store --query --requisites --include-outputs > /tmp/dependency-paths-outputs ||:;
  cat /tmp/drv-paths | xargs nix-store --query --requisites  > /tmp/dependency-paths ||:;
  # only copy the binary portions of the build-time dependencies
  awk 'NR==FNR{a[$0]=1;next}!a[$0]' /tmp/dependency-paths /tmp/dependency-paths-outputs > /tmp/paths-to-check;

  # Parse upstream caches (comma or newline separated)
  upstream_caches="${INPUT_UPSTREAM_CACHES:-https://cache.nixos.org
https://cache.flox.dev}"
  # Convert commas to newlines and remove empty lines
  upstream_caches_list=$(echo "$upstream_caches" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Add the target substituter to the list of caches to check (extract base URL without query params)
  target_substituter_base=$(echo "$CONFIGURE_NIX_SUBSTITUTER" | cut -d'?' -f1)
  if [ -n "$target_substituter_base" ]; then
    upstream_caches_list=$(printf "%s\n%s" "$upstream_caches_list" "$target_substituter_base")
  fi

  # Filter out paths that already exist in any upstream cache (including target)
  > /tmp/paths-to-push  # Create empty file
  while IFS= read -r path; do
    path_exists_in_upstream=false

    # Check if path exists in any of the upstream caches
    while IFS= read -r cache; do
      if [ -n "$cache" ] && nix path-info --store "$cache" "$path" &>/dev/null; then
        # Path exists in this upstream cache
        path_exists_in_upstream=true
        break
      fi
    done <<< "$upstream_caches_list"

    # If path doesn't exist in any upstream cache, add to push list
    if [ "$path_exists_in_upstream" = false ]; then
      echo "$path" >> /tmp/paths-to-push
    fi
  done < /tmp/paths-to-check

  # Only push paths that don't exist in any upstream cache
  if [ -s /tmp/paths-to-push ]; then
    cat /tmp/paths-to-push | xargs nix copy --extra-experimental-features nix-command --to "$CONFIGURE_NIX_SUBSTITUTER" ||:;
  else
    echo "All paths already exist in upstream caches, nothing to push"
  fi
fi
