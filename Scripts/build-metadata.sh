#!/bin/sh
# Shared checkout/build identity; needs no Swift, Node or Python runtime.
set -eu
export LC_ALL=C
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
version=$(cat "$root/VERSION")
case "$version" in *[!0-9A-Za-z.+-]*|'') printf '%s\n' 'VERSION must contain a Semantic Version, such as 0.1.0' >&2; exit 1 ;; esac
if ! awk -v value="$version" 'BEGIN {
  number="(0|[1-9][0-9]*)"
  identifier="(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
  pattern="^" number "\\." number "\\." number "(-" identifier "(\\." identifier ")*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$"
  exit !(value ~ pattern)
}'; then
  printf '%s\n' 'VERSION must contain a Semantic Version, such as 0.1.0' >&2
  exit 1
fi
build=unknown
repository=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$repository" ] && [ "$(CDPATH= cd -- "$repository" && pwd -P)" = "$root" ]; then
  build=$(git -C "$root" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || printf '%s' unknown)
fi
if [ "$build" = unknown ] && [ -f "$root/BUILD" ]; then build=$(cat "$root/BUILD"); fi
if [ "$build" != unknown ]; then
  case "$build" in *[!0-9a-fA-F]*|'') printf '%s\n' 'BUILD must contain a full Git commit hash' >&2; exit 1 ;; esac
  case "${#build}" in 40|64) ;; *) printf '%s\n' 'BUILD must contain a full Git commit hash' >&2; exit 1 ;; esac
  build=$(printf '%s' "$build" | tr 'A-F' 'a-f')
fi
short=$(printf '%.7s' "$build")
display="$version ($short)"
case "${1:-}" in
  --version) printf '%s\n' "$display" ;;
  --build) printf '%s\n' "$build" ;;
  --generate)
    [ "$#" -eq 2 ] || { printf '%s\n' 'Expected generated-source output directory' >&2; exit 1; }
    mkdir -p "$2"
    temporary=$(mktemp "$2/.metadata.XXXXXX")
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    printf '%s\n' '// Generated from VERSION and source build metadata. Do not edit.' \
      'public enum AelabVersion {' \
      "    public static let current = \"$version\"" \
      "    public static let build = \"$build\"" \
      "    public static let display = \"$display\"" \
      '}' > "$temporary"
    output="$2/AelabVersion.swift"
    if ! cmp -s "$temporary" "$output"; then mv "$temporary" "$output"; fi
    ;;
  *) printf '%s\n' 'Use --version, --build or --generate OUTPUT_DIRECTORY' >&2; exit 1 ;;
esac
