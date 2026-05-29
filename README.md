# amend-releases

Prebuilt binaries and the install script for the `amend` CLI.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/n-asuy/amend-releases/main/install.sh | bash
amend auth login
```

Pin a specific version with `AMEND_VERSION=v0.1.0`. Force a non-default
install directory with `AMEND_BIN_DIR=$HOME/bin`.

## What lives here

- `install.sh` — curl-installable installer.
- GitHub Releases (`v*.*.*`) — prebuilt `amend` binaries for
  darwin/linux × arm64/amd64.
