#!/bin/sh
# Source-level checks that need no OpenWrt: Lua 5.1 syntax, JSON, shell syntax.
set -eu
cd "$(dirname "$0")/.."

command -v luac5.1 >/dev/null 2>&1 && LUAC=luac5.1 || LUAC=luac
command -v "$LUAC" >/dev/null 2>&1 || { echo "luac (Lua 5.1) is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

find root -name '*.lua' -print | sort | while read -r f; do
    "$LUAC" -p "$f"
    echo "lua ok: $f"
done

find root -name '*.json' -print | sort | while read -r f; do
    jq -e . "$f" >/dev/null
    echo "json ok: $f"
done

for s in scripts/*; do
    [ -f "$s" ] || continue
    sh -n "$s"
    echo "sh ok: $s"
done

# Same base version in version.txt and the Makefile.
v="$(tr -d '[:space:]' < version.txt)"
m="$(sed -n 's/^PKG_VERSION:=//p' Makefile | head -n1)"
[ "$v" = "$m" ] || { echo "version.txt ($v) != Makefile PKG_VERSION ($m)" >&2; exit 1; }
echo "version ok: $v"
