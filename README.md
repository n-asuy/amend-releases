# amend-releases

Public release mirror for the [AmendFS](https://github.com/n-asuy/amendfs) CLI.
Source lives in the private repo; this repo holds prebuilt binaries and the
curl-installable script.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/n-asuy/amend-releases/main/install.sh | bash
amend auth login
```

Pin a specific version with `AMENDFS_VERSION=v0.1.0`. Force a non-default
install directory with `AMENDFS_BIN_DIR=$HOME/bin`.

## What lives here

- `install.sh` — auto-synced from `n-asuy/amendfs:scripts/install.sh` by the
  `sync-install.yml` workflow.
- GitHub Releases (`v*.*.*`) — prebuilt `amend` binaries for
  darwin/linux × arm64/amd64, published by the `release.yml` workflow on
  tag push.
