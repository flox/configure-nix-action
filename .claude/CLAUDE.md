# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a GitHub Action that configures Nix on GitHub Actions runners (Linux and macOS). It handles:
- Git, GitHub, and SSH configuration for Nix fetchers
- Configuring Nix substituters (binary caches) for uploading build artifacts
- Recording and pushing new Nix store paths to custom caches
- Remote builder configuration
- AWS credential setup for S3-based caches

## Architecture

### Entry Point: Two-Phase Execution

The action runs in two phases controlled by `src/index.js`:
1. **Main phase** (`src/main.js`): Runs at the start of the job - configures Nix, records initial store paths
2. **Post phase** (`src/post.js`): Runs at the end of the job - pushes new store paths, saves cache

This is a common pattern for GitHub Actions that need to run cleanup/upload logic after the workflow completes.

### Configuration Scripts

Scripts in `scripts/` are bash scripts that perform system-level configuration:
- **Input variables**: Scripts receive GitHub Action inputs as environment variables prefixed with `INPUT_` (e.g., `INPUT_SUBSTITUTER`, `INPUT_GIT_USER`)
- **Environment propagation**: Scripts write to `$GITHUB_ENV` to pass values between steps
- **System modification**: Most scripts use `sudo` to modify `/etc/nix/nix.conf` or system SSH configuration

Key scripts:
- `configure-substituter.sh`: Sets up binary cache for uploads, configures public keys
- `push-new-nix-store-paths.sh`: Intelligent filtering and uploading of new store paths
- `configure-post-build-hook.sh`: Sets up Nix post-build hook to track built derivations

### Cache Checking Performance

The `push-new-nix-store-paths.sh` script uses **parallel batch queries** for checking upstream caches:
- Queries all paths against each cache in a single `nix path-info` call (batching)
- Runs all cache checks in parallel using background jobs
- This achieves ~14x speedup over sequential per-path checking

The script automatically includes the target substituter in the upstream cache list to avoid re-uploading existing paths.

## Development Commands

### Environment Setup

This project uses Flox for reproducible development environments. If Flox is not installed, see https://flox.dev/docs for installation instructions.

```bash
# Activate Flox environment (provides Node.js 20)
flox activate

# Install npm dependencies
npm install
```

### Building
```bash
# Compile src/ into dist/index.js (required before testing action changes)
npm run package

# Watch mode for development
npm run package:watch

# Format and build everything
npm run bundle
```

### Testing
```bash
# Run tests with coverage
npm test

# Run tests only (no coverage badge generation)
npm run ci-test

# Format code
npm run format:write

# Check formatting
npm run format:check
```

### Performance Benchmarking
```bash
# Benchmark cache checking with defaults (350 paths, 1 run)
./scripts/benchmark-cache-check.sh

# Custom configuration
NUM_PATHS=500 NUM_RUNS=3 ./scripts/benchmark-cache-check.sh

# Test against custom caches
UPSTREAM_CACHES="https://cache.nixos.org,https://custom.cache" ./scripts/benchmark-cache-check.sh
```

The benchmark compares sequential vs parallel batch cache checking approaches.

## Important Implementation Details

### Action Inputs to Environment Variables

The `exportVariableFromInput()` utility in `src/utils.js` converts action inputs to environment variables:
- Input name `substituter-key` becomes `INPUT_SUBSTITUTER_KEY`
- Scripts can then read these standardized environment variables

### Distribution Building

Changes to `src/` must be compiled into `dist/index.js` using `@vercel/ncc`:
- GitHub Actions runs `dist/index.js`, not source files
- Always run `npm run package` after changing source code
- The `dist/` directory should be committed

### Upstream Cache Filtering

When pushing to a substituter, the action checks multiple upstream caches to avoid redundant uploads:
- Default caches: `cache.nixos.org`, `cache.flox.dev`
- Users can configure additional caches via `upstream-caches` input
- The target substituter is automatically added to the check list
- Uses `comm` for efficient set difference operations

### Post-Build Hook Mechanism

The action uses Nix's `post-build-hook` feature:
- Hook script writes derivation paths to `/tmp/drv-paths` during builds
- In the post phase, these paths are queried for their full dependency closure
- Only binary outputs (not build-time-only dependencies) are pushed
- See: https://www.haskellforall.com/2022/10/how-to-correctly-cache-build-time.html
