#!/usr/bin/env bash
# AmendFS CLI installer.
#
#   curl -fsSL https://raw.githubusercontent.com/n-asuy/amend-releases/main/install.sh | bash
#
# Downloads the prebuilt `amend` binary from
# github.com/n-asuy/amend-releases and installs it onto PATH.
#
# This file lives in n-asuy/amendfs as the source of truth and is mirrored to
# n-asuy/amend-releases (where it's actually fetched from). Edit here, then
# copy to the public repo.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
RELEASE_REPO="${AMENDFS_RELEASE_REPO:-n-asuy/amend-releases}"
BIN_NAME="amend"
PROJECT_LABEL="AmendFS CLI"

# ---------------------------------------------------------------------------
# Output helpers (disable colour when not a TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ] || [ -t 2 ]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

info()  { printf "${BOLD}${CYAN}==> %s${RESET}\n" "$*"; }
ok()    { printf "${BOLD}${GREEN}✓ %s${RESET}\n" "$*"; }
warn()  { printf "${BOLD}${YELLOW}⚠ %s${RESET}\n" "$*" >&2; }
fail()  { printf "${BOLD}${RED}✗ %s${RESET}\n" "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------
detect_platform() {
  case "$(uname -s)" in
    Darwin) OS="darwin" ;;
    Linux)  OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*)
      fail "Windows is not supported by this installer. Use WSL, or wait for a native installer." ;;
    *) fail "Unsupported operating system: $(uname -s)." ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) fail "Unsupported architecture: $(uname -m)." ;;
  esac
}

require_tools() {
  for tool in curl tar; do
    command_exists "$tool" || fail "$tool is required but not installed."
  done
  if command_exists sha256sum; then
    SHA256_CMD="sha256sum"
  elif command_exists shasum; then
    SHA256_CMD="shasum -a 256"
  else
    fail "Neither sha256sum nor shasum is available — cannot verify download."
  fi
}

# ---------------------------------------------------------------------------
# Version discovery
# ---------------------------------------------------------------------------
latest_tag() {
  # `releases/latest` 302s to the canonical tag URL. We follow the Location
  # header instead of hitting api.github.com so we don't burn unauthenticated
  # rate limit. Same trick multica and friends use.
  curl -sI "https://github.com/${RELEASE_REPO}/releases/latest" \
    | awk -F': ' 'tolower($1)=="location"{print $2}' \
    | sed 's|.*/tag/||' \
    | tr -d '\r\n'
}

resolve_tag() {
  if [ -n "${AMENDFS_VERSION:-}" ]; then
    TAG="$AMENDFS_VERSION"
    case "$TAG" in v*) ;; *) TAG="v$TAG" ;; esac
  else
    TAG="$(latest_tag)"
  fi
  if [ -z "$TAG" ]; then
    fail "Could not resolve latest release tag from github.com/${RELEASE_REPO}.
If the public release mirror has not been set up yet, ask the maintainer."
  fi
  VERSION="${TAG#v}"
}

# ---------------------------------------------------------------------------
# Already-installed check
# ---------------------------------------------------------------------------
maybe_skip_if_current() {
  if ! command_exists "$BIN_NAME"; then
    return
  fi
  # `amend --version` prints e.g. "amend 0.1.0". Strip the name and any
  # leading 'v'.
  current_ver="$("$BIN_NAME" --version 2>/dev/null | awk '{print $2}' || true)"
  current_ver="${current_ver#v}"
  if [ -n "$current_ver" ] && [ "$current_ver" = "$VERSION" ]; then
    ok "${PROJECT_LABEL} ${TAG} is already installed at $(command -v "$BIN_NAME")"
    exit 0
  fi
  if [ -n "$current_ver" ]; then
    info "Upgrading $current_ver → $VERSION"
  fi
}

# ---------------------------------------------------------------------------
# Download + checksum
# ---------------------------------------------------------------------------
download_archive() {
  ARCHIVE="amendfs-cli-${VERSION}-${OS}-${ARCH}.tar.gz"
  URL_BASE="https://github.com/${RELEASE_REPO}/releases/download/${TAG}"

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT

  info "Downloading ${ARCHIVE}"
  if ! curl -fsSL "${URL_BASE}/${ARCHIVE}" -o "${TMPDIR}/${ARCHIVE}"; then
    fail "Failed to download ${URL_BASE}/${ARCHIVE}.
This usually means the binary for your platform (${OS}/${ARCH}) was not
published for tag ${TAG}, or your network blocks github.com."
  fi

  info "Verifying checksum"
  if ! curl -fsSL "${URL_BASE}/checksums.txt" -o "${TMPDIR}/checksums.txt"; then
    fail "Failed to download checksums.txt — refusing to install unverified binary."
  fi
  expected="$(grep " ${ARCHIVE}\$" "${TMPDIR}/checksums.txt" | awk '{print $1}')"
  if [ -z "$expected" ]; then
    fail "No checksum entry for ${ARCHIVE} in checksums.txt."
  fi
  actual="$(cd "$TMPDIR" && $SHA256_CMD "$ARCHIVE" | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    fail "Checksum mismatch for ${ARCHIVE}.
  expected: $expected
  got:      $actual"
  fi
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
extract_binary() {
  tar -xzf "${TMPDIR}/${ARCHIVE}" -C "$TMPDIR" "$BIN_NAME"
  chmod +x "${TMPDIR}/${BIN_NAME}"
}

place_binary() {
  # Try, in order:
  #   1. $AMENDFS_BIN_DIR if set.
  #   2. /usr/local/bin if writable directly.
  #   3. /usr/local/bin via sudo, if sudo is available and on a tty.
  #   4. $HOME/.local/bin (and patch shell rc files).
  local candidate
  if [ -n "${AMENDFS_BIN_DIR:-}" ]; then
    candidate="$AMENDFS_BIN_DIR"
    mkdir -p "$candidate"
    install_to "$candidate" || fail "Cannot install to $candidate."
    return
  fi

  candidate="/usr/local/bin"
  if [ -w "$candidate" ]; then
    install_to "$candidate"
    return
  fi

  if command_exists sudo && [ -t 0 ]; then
    info "Installing to ${candidate} (requires sudo)"
    if sudo install -m 0755 "${TMPDIR}/${BIN_NAME}" "${candidate}/${BIN_NAME}"; then
      BIN_DIR="$candidate"
      return
    fi
    warn "sudo install to ${candidate} failed — falling back to \$HOME/.local/bin"
  fi

  candidate="$HOME/.local/bin"
  mkdir -p "$candidate"
  install_to "$candidate"
  ensure_path_for "$candidate"
}

install_to() {
  local dir="$1"
  install -m 0755 "${TMPDIR}/${BIN_NAME}" "${dir}/${BIN_NAME}"
  BIN_DIR="$dir"
}

ensure_path_for() {
  local dir="$1"
  case ":$PATH:" in
    *":$dir:"*) return ;;
  esac
  local line="export PATH=\"$dir:\$PATH\""
  local patched=0
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -qF "$dir" "$rc"; then
      printf '\n# Added by %s installer\n%s\n' "$PROJECT_LABEL" "$line" >> "$rc"
      patched=1
    fi
  done
  if [ "$patched" = 1 ]; then
    warn "Added ${dir} to PATH in ~/.bashrc / ~/.zshrc. Restart your shell or run:"
    printf "    %s\n" "$line" >&2
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  printf "\n"
  printf "${BOLD}  %s — Installer${RESET}\n" "$PROJECT_LABEL"
  printf "\n"

  detect_platform
  require_tools
  resolve_tag
  maybe_skip_if_current
  download_archive
  extract_binary
  place_binary

  printf "\n"
  ok "${PROJECT_LABEL} ${TAG} installed to ${BIN_DIR}/${BIN_NAME}"
  printf "\n"
  printf "  ${BOLD}Next:${RESET}\n"
  printf "     ${CYAN}%s auth login${RESET}\n" "$BIN_NAME"
  printf "\n"
}

main "$@"
