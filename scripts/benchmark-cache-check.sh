#!/usr/bin/env bash

set -euo pipefail

# Configuration
NUM_PATHS=${NUM_PATHS:-350}
NUM_RUNS=${NUM_RUNS:-3}
UPSTREAM_CACHES=${UPSTREAM_CACHES:-"https://cache.nixos.org
https://cache.flox.dev"}

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║        Nix Cache Check Performance Benchmark                       ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  - Number of paths: $NUM_PATHS"
echo "  - Number of runs: $NUM_RUNS"
echo "  - Caches: $(echo "$UPSTREAM_CACHES" | tr '\n' ' ')"
echo ""

# Generate random test paths (SAME paths used for both approaches)
echo "Generating $NUM_PATHS random paths from your Nix store..."
nix-store --query --requisites /run/current-system 2>/dev/null | shuf | head -n "$NUM_PATHS" > /tmp/benchmark-paths.txt
actual_paths=$(wc -l < /tmp/benchmark-paths.txt)
echo "  ✓ Generated $actual_paths paths"

# Calculate checksum to verify both approaches use identical paths
paths_checksum=$(md5sum /tmp/benchmark-paths.txt | awk '{print $1}')
echo "  ✓ Paths checksum: $paths_checksum (for verification)"
echo ""

# Read paths once - this array is shared by both approaches
mapfile -t all_paths < /tmp/benchmark-paths.txt

# Parse caches
upstream_caches_list=$(echo "$UPSTREAM_CACHES" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

#############################################
# OLD APPROACH: Sequential checking
#############################################

run_sequential_benchmark() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "OLD APPROACH: Sequential path checking"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  local total_time=0
  local run_times=()

  for run in $(seq 1 "$NUM_RUNS"); do
    echo "Run $run/$NUM_RUNS..."

    start_time=$(date +%s.%N)

    > /tmp/seq-paths-to-push

    # Sequential approach: check each path against each cache
    local checked=0
    for path in "${all_paths[@]}"; do
      path_exists_in_upstream=false

      while IFS= read -r cache; do
        if [ -n "$cache" ] && nix path-info --store "$cache" "$path" &>/dev/null 2>&1; then
          path_exists_in_upstream=true
          break
        fi
      done <<< "$upstream_caches_list"

      if [ "$path_exists_in_upstream" = false ]; then
        echo "$path" >> /tmp/seq-paths-to-push
      fi

      checked=$((checked + 1))
      if [ $((checked % 50)) -eq 0 ]; then
        echo -ne "  Progress: $checked/$actual_paths paths checked\r"
      fi
    done

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    run_times+=("$duration")
    total_time=$(echo "$total_time + $duration" | bc)

    echo -ne "\033[K"  # Clear line
    echo "  ✓ Run $run: ${duration}s"
  done

  avg_time=$(echo "scale=2; $total_time / $NUM_RUNS" | bc)

  echo ""
  echo "Results:"
  echo "  - Average time: ${avg_time}s"
  echo "  - All runs: ${run_times[*]}"
  echo "  - Paths checked: ${#all_paths[@]}"
  echo "  - Paths to push: $(wc -l < /tmp/seq-paths-to-push)"
  echo ""

  # Return average time (write to file for capture)
  echo "$avg_time" > /tmp/benchmark-seq-avg.txt
}

#############################################
# NEW APPROACH: Parallel batch checking
#############################################

run_parallel_benchmark() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "NEW APPROACH: Parallel batch checking"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  local total_time=0
  local run_times=()

  for run in $(seq 1 "$NUM_RUNS"); do
    echo "Run $run/$NUM_RUNS..."

    start_time=$(date +%s.%N)

    cache_results_dir=$(mktemp -d)

    # For each cache, check all paths in a single batch query (in parallel)
    cache_index=0
    while IFS= read -r cache; do
      if [ -n "$cache" ]; then
        (
          nix path-info --store "$cache" "${all_paths[@]}" 2>/dev/null > "$cache_results_dir/cache-$cache_index.txt" || true
        ) &
        cache_index=$((cache_index + 1))
      fi
    done <<< "$upstream_caches_list"

    # Wait for all parallel cache checks to complete
    wait

    # Combine all paths found in any cache into a single file
    cat "$cache_results_dir"/cache-*.txt 2>/dev/null | sort -u > /tmp/par-paths-in-caches || true

    # Find paths that are NOT in any cache (paths to push)
    if [ -s /tmp/par-paths-in-caches ]; then
      comm -23 <(printf "%s\n" "${all_paths[@]}" | sort) /tmp/par-paths-in-caches > /tmp/par-paths-to-push
    else
      printf "%s\n" "${all_paths[@]}" > /tmp/par-paths-to-push
    fi

    rm -rf "$cache_results_dir"

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    run_times+=("$duration")
    total_time=$(echo "$total_time + $duration" | bc)

    echo "  ✓ Run $run: ${duration}s"
  done

  avg_time=$(echo "scale=2; $total_time / $NUM_RUNS" | bc)

  echo ""
  echo "Results:"
  echo "  - Average time: ${avg_time}s"
  echo "  - All runs: ${run_times[*]}"
  echo "  - Paths checked: ${#all_paths[@]}"
  echo "  - Paths to push: $(wc -l < /tmp/par-paths-to-push)"
  echo ""

  # Return average time (write to file for capture)
  echo "$avg_time" > /tmp/benchmark-par-avg.txt
}

#############################################
# Run benchmarks
#############################################

# Warn user about sequential benchmark
echo "⚠️  WARNING: The sequential benchmark will be SLOW!"
echo "   It makes N × M network requests (paths × caches)"
echo "   For 350 paths × 2 caches = ~700 requests"
echo ""
read -p "Run sequential benchmark? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  run_sequential_benchmark
  SEQUENTIAL_AVG=$(cat /tmp/benchmark-seq-avg.txt)
else
  echo "Skipping sequential benchmark..."
  echo ""
  SEQUENTIAL_AVG="N/A"
fi

# Run parallel benchmark
run_parallel_benchmark
PARALLEL_AVG=$(cat /tmp/benchmark-par-avg.txt)

#############################################
# Summary
#############################################

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                         BENCHMARK SUMMARY                          ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  - Paths checked: $actual_paths (checksum: $paths_checksum)"
echo "  - Caches: $(echo "$upstream_caches_list" | wc -l)"
echo "  - Runs per approach: $NUM_RUNS"
echo ""
echo "✓ Both approaches tested against identical path set"
echo ""
echo "Results:"

if [ "$SEQUENTIAL_AVG" != "N/A" ]; then
  echo "  - Sequential approach: ${SEQUENTIAL_AVG}s average"
  echo "  - Parallel approach:   ${PARALLEL_AVG}s average"
  speedup=$(echo "scale=2; $SEQUENTIAL_AVG / $PARALLEL_AVG" | bc)
  echo ""
  echo "  🚀 SPEEDUP: ${speedup}x faster with parallel approach!"
else
  echo "  - Parallel approach: ${PARALLEL_AVG}s average"
  echo ""
  echo "  (Sequential benchmark was skipped)"
fi
echo ""
echo "════════════════════════════════════════════════════════════════════"

# Cleanup
rm -f /tmp/benchmark-paths.txt /tmp/seq-paths-to-push /tmp/par-paths-to-push /tmp/par-paths-in-caches /tmp/benchmark-seq-avg.txt /tmp/benchmark-par-avg.txt
