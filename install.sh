#!/usr/bin/env bash
# install.sh -- fetches a verified, tagged release of baize and hands off to
# `baize install`. Piped from `curl | bash`, so this file must stay small
# enough to read in one sitting before trusting it.
#
# Everything after `bash -s --` in the one-liner is forwarded verbatim to
# `baize install`; this script never parses those flags itself so adding one
# later needs no change here.
set -euo pipefail

REPO="Dylan0203/baize"
BIN_DIR="$HOME/.local/bin"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'install.sh: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

# Prints the tag to install, e.g. "v0.1.0", on stdout.
#
# Never falls back to `main`: a failed or unparseable API response is an
# error, not a silent downgrade to an unversioned build. This mirrors
# `baize update`'s resolution exactly (see docs/baize-v0-1 shared context on
# the paired-change surface) -- change one, change both.
resolve_version() {
  if [[ -n "${BAIZE_VERSION:-}" ]]; then
    printf '%s\n' "$BAIZE_VERSION"
    return 0
  fi

  local response
  response="$(curl -fsSL --max-time 10 "https://api.github.com/repos/$REPO/releases/latest")" || {
    printf 'install.sh: could not reach the GitHub releases API. Refusing to fall back to an unversioned build.\n' >&2
    return 1
  }

  # No JSON parser dependency -- the host is not allowed to need one. grep
  # the well-known tag_name field and pull its value with sed.
  local tag
  tag="$(printf '%s\n' "$response" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

  if [[ -z "$tag" ]]; then
    printf 'install.sh: could not find a tag_name in the releases API response.\n' >&2
    return 1
  fi

  printf '%s\n' "$tag"
}

download() {
  local version="$1" dir="$2"
  curl -fsSL --max-time 30 -o "$dir/baize" \
    "https://github.com/$REPO/releases/download/$version/baize"
  curl -fsSL --max-time 30 -o "$dir/SHA256SUMS" \
    "https://github.com/$REPO/releases/download/$version/SHA256SUMS"
}

# Verifies $dir/baize against $dir/SHA256SUMS.
#
# Be honest about what this buys: SHA256SUMS travels the same HTTPS channel
# as the artifact, so it catches a truncated or corrupted download -- not a
# MITM or a compromised release. The real trust anchor is GitHub's TLS plus
# the account, not this checksum. It is not a signature.
verify() {
  local dir="$1"

  # `sha256sum -c --ignore-missing` succeeds vacuously if SHA256SUMS lists
  # nothing we downloaded. Confirm baize is actually named in it before
  # trusting a pass -- otherwise a truncated or empty SHA256SUMS would let
  # an unverified binary through.
  grep -q '[[:space:]]baize$' "$dir/SHA256SUMS" || {
    printf 'install.sh: SHA256SUMS does not list baize. Refusing to install.\n' >&2
    exit 1
  }

  ( cd "$dir" && sha256sum -c --ignore-missing SHA256SUMS ) || {
    printf 'install.sh: checksum verification FAILED. Refusing to install.\n' >&2
    exit 1
  }
}

place() {
  local dir="$1"
  mkdir -p "$BIN_DIR"
  chmod +x "$dir/baize"
  mv -f "$dir/baize" "$BIN_DIR/baize"
}

# ~/.local/bin is on PATH by default on Ubuntu only when it exists at login
# -- a fresh box that just created it this second will not have it until
# re-login. Warn, do not fail.
warn_if_not_on_path() {
  case ":${PATH}:" in
    *":$BIN_DIR:"*) return 0 ;;
  esac
  printf 'install.sh: warning: %s is not on your PATH yet.\n' "$BIN_DIR" >&2
  printf '  Add this to your shell profile (e.g. ~/.bashrc or ~/.zshrc), then re-login or re-source it:\n' >&2
  # shellcheck disable=SC2016  # $PATH here is literal text for the user to paste, not meant to expand
  printf '    export PATH="%s:$PATH"\n' "$BIN_DIR" >&2
}

hand_off() {
  local version="$1"; shift
  printf 'Installed baize %s to %s\n' "$version" "$BIN_DIR/baize"
  "$BIN_DIR/baize" install "$@"
}

main() {
  # baize installs into your own home and needs no privileges. A root
  # install would land in /root/.local/bin with a root crontab -- not what
  # anyone asked for, and it will be found months later by someone confused.
  if [[ "$(id -u)" -eq 0 ]]; then
    printf 'install.sh: do not run as root. baize installs into your own home and needs no privileges.\n' >&2
    exit 1
  fi

  need_cmd curl
  need_cmd sha256sum

  local version; version="$(resolve_version)"

  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  download "$version" "$tmp"
  verify "$tmp"
  place "$tmp"
  warn_if_not_on_path

  # Exit explicitly with `baize install`'s own status, still inside this
  # function's scope, rather than falling off the end and returning to top
  # level: the EXIT trap above references $tmp, a local variable that bash
  # unsets the instant main returns, which would otherwise trip `set -u` on
  # a clean, successful run.
  local rc=0
  hand_off "$version" "$@" || rc="$?"
  exit "$rc"
}

main "$@"
