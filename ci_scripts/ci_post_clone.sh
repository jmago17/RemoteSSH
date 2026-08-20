#!/bin/sh
#
# ci_post_clone.sh — regenerate the Xcode project before Xcode Cloud builds.
#
# WHY THIS EXISTS
# ---------------
# RemoteSSH.xcodeproj is deliberately NOT in git: XcodeGen generates it from
# project.yml (see .gitignore). Xcode Cloud clones the repo and immediately
# looks for the project file, so without this script every build dies with:
#
#     Project RemoteSSH.xcodeproj does not exist at the root of the repository
#
# The same applies to RemoteSSH-Info.plist and RemoteSSH.entitlements, which
# project.yml also generates.
#
# NOTES
# -----
# - Xcode Cloud runs this from ci_scripts/, so we cd to the repo root using
#   CI_PRIMARY_REPOSITORY_PATH (source code is not guaranteed to be at $PWD).
# - sudo is NOT available in Xcode Cloud, so we install XcodeGen by unpacking
#   the official release zip into $HOME instead of using Homebrew (brew is slow
#   here and can need paths we cannot write).
# - The version is pinned to match the Mac, so CI and local generation cannot
#   drift apart.

set -e

XCODEGEN_VERSION="2.45.4"

echo "--- ci_post_clone: generating RemoteSSH.xcodeproj with XcodeGen ${XCODEGEN_VERSION} ---"

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT"
echo "Repo root: $(pwd)"

if [ ! -f project.yml ]; then
    echo "error: project.yml not found at the repository root."
    exit 1
fi

# Install XcodeGen into a writable, throwaway location.
TOOLS_DIR="$HOME/.xcodegen-${XCODEGEN_VERSION}"
XCODEGEN_BIN="$TOOLS_DIR/xcodegen/bin/xcodegen"

if [ ! -x "$XCODEGEN_BIN" ]; then
    echo "Downloading XcodeGen ${XCODEGEN_VERSION}…"
    mkdir -p "$TOOLS_DIR"
    curl -fsSL --retry 3 --retry-delay 2 \
        "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip" \
        -o "$TOOLS_DIR/xcodegen.zip"
    unzip -q -o "$TOOLS_DIR/xcodegen.zip" -d "$TOOLS_DIR"
    chmod +x "$XCODEGEN_BIN"
fi

"$XCODEGEN_BIN" --version

# XcodeGen stamps the project's developer attributes from $USER and fails with
# "Couldn't find current username" if it is unset. Xcode Cloud normally sets it,
# but a sanitised environment may not — fall back to whoami so generation cannot
# depend on that.
if [ -z "${USER:-}" ]; then
    USER="$(whoami 2>/dev/null || echo ci)"
    export USER
    echo "USER was unset; using '$USER'."
fi

"$XCODEGEN_BIN" generate \
    --spec project.yml \
    --project "$REPO_ROOT" \
    --no-env

if [ ! -d "RemoteSSH.xcodeproj" ]; then
    echo "error: XcodeGen finished but RemoteSSH.xcodeproj is missing."
    exit 1
fi

echo "--- Generated successfully ---"
ls -d RemoteSSH.xcodeproj RemoteSSH-Info.plist RemoteSSH.entitlements 2>/dev/null || true
