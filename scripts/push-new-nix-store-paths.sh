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
  # Use batched queries and parallel execution for better performance

  # Read all paths into an array for batch processing
  mapfile -t all_paths < /tmp/paths-to-check

  # Create temp directory for parallel cache check results
  cache_results_dir=$(mktemp -d)

  # For each cache, check all paths in a single batch query (in parallel)
  cache_index=0
  while IFS= read -r cache; do
    if [ -n "$cache" ]; then
      (
        # Query this cache for all paths at once, output existing paths to a file
        # nix path-info returns only the paths that exist
        nix path-info --store "$cache" "${all_paths[@]}" 2>/dev/null > "$cache_results_dir/cache-$cache_index.txt" || true
      ) &
      cache_index=$((cache_index + 1))
    fi
  done <<< "$upstream_caches_list"

  # Wait for all parallel cache checks to complete
  wait

  # Combine all paths found in any cache into a single file
  cat "$cache_results_dir"/cache-*.txt 2>/dev/null | sort -u > /tmp/paths-in-caches || true

  # Find paths that are NOT in any cache (paths to push)
  if [ -s /tmp/paths-in-caches ]; then
    # Use comm to find paths in paths-to-check but not in paths-in-caches
    comm -23 <(sort /tmp/paths-to-check) /tmp/paths-in-caches > /tmp/paths-to-push
  else
    # No paths found in any cache, push everything
    cp /tmp/paths-to-check /tmp/paths-to-push
  fi

  # Clean up temp directory
  rm -rf "$cache_results_dir"

  # Only push paths that don't exist in any upstream cache
  if [ -s /tmp/paths-to-push ]; then
    cat /tmp/paths-to-push | xargs nix copy --extra-experimental-features nix-command --to "$CONFIGURE_NIX_SUBSTITUTER" ||:;
  else
    echo "All paths already exist in upstream caches, nothing to push"
  fi
fi
