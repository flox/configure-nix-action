
Configures Nix on GitHub Actions for the supported platforms: Linux and macOS.


## ⭐ Getting Started

Create `.github/workflows/ci.yml` in your repo with the following contents:

```yml
name: "CI"

on:
  pull_request:
  push:

jobs:
  tests:
    runs-on: ubuntu-latest
    steps:

    - name: Checkout
      uses: actions/checkout@v3

    - name: Install Nix
      uses: cachix/install-nix-action

    - name: Configure Nix
      uses: flox/configure-nix-action
      with: ...options...

    - name: Build
      run: nix build ...
```

### 🚀 Options

See `./action.yml` file.

## 🔧 Development

### Setup Development Environment

This project uses [Flox](https://flox.dev) for reproducible development environments.

1. **Install Flox** (if not already installed)

   See [Flox installation instructions](https://flox.dev/docs)

2. **Clone the repository**
   ```bash
   git clone https://github.com/flox/configure-nix-action.git
   cd configure-nix-action
   ```

3. **Activate the Flox environment**
   ```bash
   flox activate
   ```
   This automatically installs Node.js 20 and all required dependencies.

4. **Install npm dependencies**
   ```bash
   npm install
   ```

5. **Make changes to the source code**
   - Edit files in `src/` directory
   - Modify scripts in `scripts/` directory

6. **Build the distribution**
   ```bash
   npm run package
   ```
   This compiles `src/` into `dist/index.js` which is what GitHub Actions runs.

7. **Run tests**
   ```bash
   npm test
   ```

### Performance Benchmarking

A benchmark script is available to measure cache checking performance:

```bash
./scripts/benchmark-cache-check.sh
```

**Configuration via environment variables:**

```bash
# Customize number of paths to test (default: 350)
NUM_PATHS=500 ./scripts/benchmark-cache-check.sh

# Run multiple iterations (default: 1)
NUM_RUNS=3 ./scripts/benchmark-cache-check.sh

# Test against custom caches (default: cache.nixos.org, cache.flox.dev)
UPSTREAM_CACHES="https://cache.nixos.org,https://custom-cache.com" ./scripts/benchmark-cache-check.sh
```

The benchmark compares two approaches:
- **Sequential**: Checks each path against each cache one at a time (legacy)
- **Parallel Batch**: Checks all paths against all caches in parallel (current)

**Example results** (500 paths, 2 caches):
- Sequential: ~153s
- Parallel: ~10s
- **Speedup: 14.5x faster** 🚀

