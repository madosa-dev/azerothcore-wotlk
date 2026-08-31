#!/usr/bin/env bash
# Build MadosaLauncher.exe from madosa_launcher.py.
#
#     ./build_exe.sh
#
# PyInstaller cannot cross-compile - a Windows executable has to be built by a
# Windows Python - so this puts one inside its own Wine prefix and builds there.
# The prefix is kept out of ~/.wine on purpose: this is a build tool, and it has
# no business installing anything into the prefix the games use. Delete
# $BUILD_ROOT to undo everything this script ever did.
#
# Everything is cached, so a second run only re-runs PyInstaller.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$HOME/.cache/madosa-launcher-build}"
export WINEPREFIX="$BUILD_ROOT/prefix"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="mscoree,mshtml="   # skip the Mono/Gecko install prompts

# 3.12 rather than the newest: PyInstaller support lands there first, and a
# version Wine is known to run beats a version that is merely current.
PYTHON_VERSION="${PYTHON_VERSION:-3.12.8}"
PYTHON_INSTALLER="python-${PYTHON_VERSION}-amd64.exe"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_INSTALLER}"

# Where the installer puts a per-user install inside the prefix.
WIN_PYTHON="$WINEPREFIX/drive_c/users/$USER/AppData/Local/Programs/Python/Python312/python.exe"

say() { printf '\n== %s\n' "$*"; }

command -v wine >/dev/null || { echo "wine is not installed" >&2; exit 1; }
mkdir -p "$BUILD_ROOT/downloads"

if [[ ! -d "$WINEPREFIX" ]]; then
    say "creating the build prefix at $WINEPREFIX"
    wineboot --init >/dev/null 2>&1 || true
    wineserver -w
fi

if [[ ! -f "$BUILD_ROOT/downloads/$PYTHON_INSTALLER" ]]; then
    say "downloading Python $PYTHON_VERSION for Windows"
    curl -fL --progress-bar -o "$BUILD_ROOT/downloads/$PYTHON_INSTALLER" "$PYTHON_URL"
fi

if [[ ! -f "$WIN_PYTHON" ]]; then
    say "installing Python into the prefix (this takes a minute)"
    # InstallAllUsers=0 keeps it in the user profile, where no elevation is
    # needed; Include_test=0 drops the test suite, which is most of the size.
    wine "$BUILD_ROOT/downloads/$PYTHON_INSTALLER" /quiet \
        InstallAllUsers=0 PrependPath=1 Include_test=0 Include_launcher=0 || true
    wineserver -w
fi

[[ -f "$WIN_PYTHON" ]] || { echo "Python did not install - look in $WINEPREFIX" >&2; exit 1; }

say "Python in the prefix"
wine "$WIN_PYTHON" --version

if ! wine "$WIN_PYTHON" -c "import PyInstaller" >/dev/null 2>&1; then
    say "installing PyInstaller"
    wine "$WIN_PYTHON" -m pip install --disable-pip-version-check --no-input pyinstaller
    wineserver -w
fi

say "building"
cd "$HERE"
rm -rf build dist MadosaLauncher.spec
# --onefile so a player gets one thing; --windowed so double-clicking does not
# leave a console window behind the launcher's own window.
wine "$WIN_PYTHON" -m PyInstaller \
    --onefile --windowed --name MadosaLauncher \
    --distpath dist --workpath build --specpath . \
    madosa_launcher.py
wineserver -w

if [[ -f dist/MadosaLauncher.exe ]]; then
    say "done: $(du -h dist/MadosaLauncher.exe | cut -f1)  ->  $HERE/dist/MadosaLauncher.exe"
else
    echo "the build produced no executable" >&2
    exit 1
fi
