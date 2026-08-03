
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
      uses: actions/checkout@v7

    - name: Install Nix
      uses: cachix/install-nix-action@v31

    - name: Configure Nix
      uses: flox/configure-nix-action@main
      with: ...options...

    - name: Build
      run: nix build ...
```

### 🚀 Options

See `./action.yml` file.

