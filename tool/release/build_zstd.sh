#!/usr/bin/env bash
# בונה את ה-CLI של zstd שנארז לצד אוצריא ב-macOS וב-Linux — הוא שמפענח
# אצל המשתמש את חבילת העדכון המצומצם. מקוד המקור של facebook/zstd בגרסה
# נעולה ב-hash: ל-macOS אין בינארי רשמי, ובקונטיינר ה-Linux ה-zstd של
# ההפצה תלוי בספריות משותפות שאינן מובטחות אצל המשתמש.
#
# usage: build_zstd.sh <output-file> [universal]
#   universal — בינארי macOS אחד ל-x86_64 ול-arm64 (אותו bundle לשניהם).
set -euo pipefail

out=${1:?usage: build_zstd.sh <output-file> [universal]}
mode=${2:-native}

version=1.5.7
sha256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -fsSL --retry 3 -o "$work/zstd.tar.gz" \
  "https://github.com/facebook/zstd/releases/download/v$version/zstd-$version.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$work/zstd.tar.gz" | cut -d' ' -f1)
else
  actual=$(shasum -a 256 "$work/zstd.tar.gz" | cut -d' ' -f1)
fi
if [ "$actual" != "$sha256" ]; then
  echo "::error::zstd-$version.tar.gz hash mismatch: $actual" >&2
  exit 1
fi
tar -xzf "$work/zstd.tar.gz" -C "$work"

# בלי zlib/lzma/lz4: הם היו נקשרים דינמית לספריות של מכונת הבנייה.
more_flags=""
if [ "$mode" = universal ]; then
  more_flags="-arch x86_64 -arch arm64 -mmacosx-version-min=12.0"
fi
make -C "$work/zstd-$version/programs" -j4 zstd \
  HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 MOREFLAGS="$more_flags" >/dev/null

built="$work/zstd-$version/programs/zstd"
"$built" --version
if [ "$mode" = universal ]; then
  lipo "$built" -verify_arch x86_64 arm64
fi
mkdir -p "$(dirname "$out")"
cp "$built" "$out.partial"
chmod 755 "$out.partial"
mv "$out.partial" "$out"
echo "zstd $version -> $out"
