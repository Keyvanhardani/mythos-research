#!/bin/bash
# =============================================================================
# build-sandbox.sh — Per-language build helpers for v4 live-hunt phase.
#
# Sets up a scratch dir with the target package built (for hunters' Bash usage)
# and emits a JSON descriptor on stdout describing what's available.
#
# Usage:
#   build-sandbox.sh <target-dir> <scratch-dir> [language]
#
# Stdout: single-line JSON like
#   {"language":"python","ready":true,"python":"/path/.venv/bin/python",
#    "scratch":"/tmp/...","note":"venv built, package installed"}
#
# Exit 0 if scratch dir is usable (even partially). Exit 1 only on hard error.
# Build failures are reported with "ready":false but do NOT fail the script —
# hunters can still operate in read-only mode and improvise.
# =============================================================================
set -euo pipefail

TARGET="${1:?Usage: build-sandbox.sh <target-dir> <scratch-dir> [language]}"
SCRATCH="${2:?scratch dir required}"
LANG_HINT="${3:-}"

[ -d "$TARGET" ] || { echo "{\"ready\":false,\"error\":\"target not a dir: $TARGET\"}" >&2; exit 1; }
mkdir -p "$SCRATCH"
chmod 700 "$SCRATCH"

INSTALL_LOG="$SCRATCH/.build.log"
: > "$INSTALL_LOG"

detect_lang() {
    local t="$1"
    if   [ -f "$t/pyproject.toml" ] || [ -f "$t/setup.py" ] || [ -f "$t/setup.cfg" ]; then echo python
    elif [ -f "$t/package.json" ]; then echo node
    elif [ -f "$t/Cargo.toml" ]; then echo rust
    elif [ -f "$t/CMakeLists.txt" ]; then echo c-cpp-cmake
    elif [ -f "$t/configure" ] || [ -f "$t/configure.ac" ]; then echo c-cpp-autotools
    elif [ -f "$t/Makefile" ] || [ -f "$t/makefile" ]; then echo c-cpp-make
    elif [ -f "$t/go.mod" ]; then echo go
    elif [ -f "$t/composer.json" ]; then echo php
    else echo generic; fi
}
# Normalise common short hints from mythos-v3/v4 (which use sink-slicer tags)
# to the finer-grained labels we case on below.
case "$LANG_HINT" in
    js-ts|js|ts|javascript|typescript)
        if [ -f "$TARGET/package.json" ]; then LANG_HINT=node; fi
        ;;
    c-cpp|c|cpp)
        if   [ -f "$TARGET/CMakeLists.txt" ];                               then LANG_HINT=c-cpp-cmake
        elif [ -f "$TARGET/configure" ] || [ -f "$TARGET/configure.ac" ];   then LANG_HINT=c-cpp-autotools
        elif [ -f "$TARGET/Makefile" ] || [ -f "$TARGET/makefile" ];        then LANG_HINT=c-cpp-make
        fi
        ;;
esac
LANG="${LANG_HINT:-$(detect_lang "$TARGET")}"

emit() {
    # emit single-line JSON descriptor on stdout
    local ready="$1" note="$2" extra_kv="$3"
    local pyready="False"
    [ "$ready" = "true" ] && pyready="True"
    LANG_OUT="$LANG_OUT" SCRATCH="$SCRATCH" TARGET="$TARGET" \
    NOTE="$note" EXTRA_KV="$extra_kv" PYREADY="$pyready" \
    python3 - <<'PY'
import json, os
out = {
    "language":  os.environ.get("LANG_OUT", "unknown"),
    "ready":     os.environ.get("PYREADY") == "True",
    "scratch":   os.environ["SCRATCH"],
    "target":    os.environ["TARGET"],
    "note":      os.environ.get("NOTE",""),
}
extra = os.environ.get("EXTRA_KV","")
if extra.strip():
    for kv in extra.split(","):
        if "=" in kv:
            k, v = kv.split("=", 1)
            out[k.strip()] = v.strip()
print(json.dumps(out, ensure_ascii=False))
PY
}

build_python() {
    LANG_OUT="python"
    if ! python3 -m venv "$SCRATCH/.venv" --system-site-packages >> "$INSTALL_LOG" 2>&1; then
        python3 -m venv "$SCRATCH/.venv" >> "$INSTALL_LOG" 2>&1 || {
            emit false "venv creation failed" "" ; return 0;
        }
    fi
    local pip="$SCRATCH/.venv/bin/pip"
    if ! "$pip" install --quiet --disable-pip-version-check --no-cache-dir "$TARGET" >> "$INSTALL_LOG" 2>&1; then
        "$pip" install --quiet --disable-pip-version-check --no-cache-dir -e "$TARGET" >> "$INSTALL_LOG" 2>&1 || {
            emit false "pip install failed; PYTHONPATH=$TARGET still usable" \
                 "python=$SCRATCH/.venv/bin/python,pythonpath=$TARGET" ; return 0;
        }
    fi
    emit true "venv built, package installed" "python=$SCRATCH/.venv/bin/python"
}

build_node() {
    LANG_OUT="node"
    (cd "$SCRATCH" && npm init -y >> "$INSTALL_LOG" 2>&1) || {
        emit false "npm init failed" "" ; return 0;
    }
    if (cd "$SCRATCH" && npm install --silent --no-audit --no-fund "$TARGET" >> "$INSTALL_LOG" 2>&1); then
        emit true "node_modules installed from target" "node_modules=$SCRATCH/node_modules"
    else
        emit false "npm install failed; require('$TARGET') still possible" "target_path=$TARGET"
    fi
}

build_rust() {
    LANG_OUT="rust"
    # cargo builds are heavy; mark scratch ready but don't pre-build.
    emit true "cargo build deferred to hunter" "cargo_manifest=$TARGET/Cargo.toml"
}

build_c_cpp_cmake() {
    LANG_OUT="c-cpp"
    local build_dir="$SCRATCH/build"
    mkdir -p "$build_dir"
    # Try ASan + debug build. If it fails, still mark scratch ready — hunter can
    # run cmake itself.
    if cmake -S "$TARGET" -B "$build_dir" \
            -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_C_FLAGS="-fsanitize=address -g -O0" \
            -DCMAKE_CXX_FLAGS="-fsanitize=address -g -O0" \
            >> "$INSTALL_LOG" 2>&1; then
        if cmake --build "$build_dir" --parallel "$(nproc 2>/dev/null || echo 2)" >> "$INSTALL_LOG" 2>&1; then
            emit true "cmake+ASan build complete" "build_dir=$build_dir,sanitizer=asan"
            return 0
        fi
    fi
    emit false "cmake build failed; hunter may rebuild manually with CC='gcc -fsanitize=address -g'" \
         "build_dir=$build_dir"
}

build_c_cpp_autotools() {
    LANG_OUT="c-cpp"
    # autotools is target-specific; do not attempt autoconf in CI here. Just note.
    emit true "autotools detected; build deferred to hunter" "configure=$TARGET/configure"
}

build_c_cpp_make() {
    LANG_OUT="c-cpp"
    # plain Makefile is too varied to safely auto-build. Note and defer.
    emit true "plain Makefile detected; build deferred to hunter" "makefile=$TARGET/Makefile"
}

build_go() {
    LANG_OUT="go"
    if (cd "$TARGET" && go build ./... >> "$INSTALL_LOG" 2>&1); then
        emit true "go build ./... succeeded" ""
    else
        emit false "go build failed; module still importable" ""
    fi
}

build_php() {
    LANG_OUT="php"
    # Composer install is risky (network, deps); just note presence.
    if [ -d "$TARGET/vendor" ]; then
        emit true "composer vendor/ already present" "vendor=$TARGET/vendor"
    else
        emit false "no vendor/ directory; run composer install separately if needed" ""
    fi
}

build_generic() {
    LANG_OUT="generic"
    emit true "no recognised build system; hunter improvises in scratch" ""
}

case "$LANG" in
    python)              build_python ;;
    node)                build_node ;;
    rust)                build_rust ;;
    c-cpp-cmake)         build_c_cpp_cmake ;;
    c-cpp-autotools)     build_c_cpp_autotools ;;
    c-cpp-make)          build_c_cpp_make ;;
    go)                  build_go ;;
    php)                 build_php ;;
    *)                   build_generic ;;
esac
