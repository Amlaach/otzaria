#!/bin/sh
# Writes the header that embeds the release tag. The tag comes only from the
# environment and is checked against ^[0-9A-Za-z.+_-]*$, so it can hold no
# quote or backslash and is safe inside a C string literal.
set -eu
# Byte ranges in the pattern below; other locales may collate A-Z differently.
export LC_ALL=C
out="$1"
tag="${OTZARIA_ASSISTANT_RELEASE_TAG:-}"

case "$tag" in
  *[!0-9A-Za-z.+_-]*)
    echo "gen_build_info.sh: invalid OTZARIA_ASSISTANT_RELEASE_TAG: '$tag'" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "$out")"
tmp="$out.tmp"
printf '#pragma once\n#define OTZ_EMBEDDED_RELEASE_TAG "%s"\n' "$tag" > "$tmp"
# Rewritten only on change, so an unchanged tag does not force a rebuild.
if [ -f "$out" ] && cmp -s "$tmp" "$out"; then
  rm -f "$tmp"
else
  mv -f "$tmp" "$out"
fi
