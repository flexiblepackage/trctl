#!/bin/sh
#
# trctl installer.
#
#   curl -fsSL https://raw.githubusercontent.com/flexiblepackage/trctl/main/install.sh | sh
#
# In CI, always pin a version — a tool that silently changes behaviour between builds
# is worse than no tool:
#
#   curl -fsSL .../install.sh | TRCTL_VERSION=v0.2.0 TRCTL_INSTALL_DIR=./bin sh
#
# Environment:
#   TRCTL_VERSION      tag to install, e.g. v0.2.0. Defaults to the latest release, with a warning.
#   TRCTL_INSTALL_DIR  where to put the binary. Defaults to /usr/local/bin.
#
# POSIX sh on purpose: it has to run on whatever the build agent happens to have.

set -eu

REPO="flexiblepackage/trctl"
ASSET="trctl_linux_amd64"
VERSION="${TRCTL_VERSION:-}"
INSTALL_DIR="${TRCTL_INSTALL_DIR:-/usr/local/bin}"

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# --- the platform this tool is built for -------------------------------------
# Only linux/amd64 is published. Say so plainly rather than installing a binary
# that cannot run: "exec format error" three steps later is a bad way to find out.
os=$(uname -s 2>/dev/null || echo unknown)
arch=$(uname -m 2>/dev/null || echo unknown)
case "$os/$arch" in
	Linux/x86_64 | Linux/amd64) ;;
	*) die "only linux/amd64 is published; this machine is $os/$arch" ;;
esac

# --- how to fetch ------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
	fetch() { curl -fsSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
	fetch() { wget -qO "$2" "$1"; }
else
	die "neither curl nor wget is available"
fi

# --- how to verify -----------------------------------------------------------
# No checksum tool means no verification, and installing an unverified binary
# quietly is exactly the kind of thing this tool exists not to do.
if command -v sha256sum >/dev/null 2>&1; then
	checksum() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
	checksum() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
	die "no sha256sum or shasum available; refusing to install without verifying the download"
fi

if [ -n "$VERSION" ]; then
	base="https://github.com/$REPO/releases/download/$VERSION"
	label="$VERSION"
else
	base="https://github.com/$REPO/releases/latest/download"
	label="the latest release"
	warn "install.sh: no TRCTL_VERSION set, installing $label."
	warn "install.sh: pin a version in CI so builds stay reproducible."
fi

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t trctl)
trap 'rm -rf "$tmp"' EXIT INT TERM

say "downloading trctl ($label) for linux/amd64"
fetch "$base/$ASSET" "$tmp/$ASSET" || die "could not download $base/$ASSET"
fetch "$base/checksums.txt" "$tmp/checksums.txt" || die "could not download the checksum file from $base"

want=$(grep " \{1,2\}$ASSET\$" "$tmp/checksums.txt" | cut -d' ' -f1)
[ -n "$want" ] || die "checksums.txt has no entry for $ASSET"

got=$(checksum "$tmp/$ASSET")
if [ "$got" != "$want" ]; then
	die "checksum mismatch for $ASSET
  expected $want
  got      $got
the download is corrupt or has been tampered with; nothing was installed"
fi
say "sha256 verified: $got"

chmod +x "$tmp/$ASSET"

# Confirm it actually runs here before putting it on the PATH. A binary that
# cannot execute is better discovered now than on the next build.
installed_version=$("$tmp/$ASSET" --version 2>/dev/null) || die "the downloaded binary does not run on this machine"
if [ -n "$VERSION" ]; then
	case "$installed_version" in
		*"$VERSION"*) ;;
		*) die "asked for $VERSION but the binary reports '$installed_version'" ;;
	esac
fi

mkdir -p "$INSTALL_DIR" 2>/dev/null || die "cannot create $INSTALL_DIR"
target="$INSTALL_DIR/trctl"

# mv across filesystems can fail; fall back to cp. Write to a neighbouring temp
# name first so an interrupted install never leaves a half-written binary in place.
if ! mv "$tmp/$ASSET" "$target.new" 2>/dev/null; then
	cp "$tmp/$ASSET" "$target.new" || die "cannot write to $INSTALL_DIR (need sudo, or set TRCTL_INSTALL_DIR)"
fi
chmod +x "$target.new"
mv "$target.new" "$target" || die "cannot install into $INSTALL_DIR"

say "installed $installed_version -> $target"

case ":$PATH:" in
	*":$INSTALL_DIR:"*) ;;
	*) warn "note: $INSTALL_DIR is not on PATH; call it as $target" ;;
esac
