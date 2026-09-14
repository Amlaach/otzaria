#!/usr/bin/env bash
# Fetch the prebuilt library search index that Otzaria/SeforimLibrary publishes
# alongside every database release, and verify it belongs to THIS build.
#
#   fetch_prebuilt_library_index.sh <index-dir> <seforim.db.zst> \
#       <talmud_bavli_latest.tar.zst> <pubspec.lock>
#
# רקע: בעבר כל בנייה הריצה `otzaria build-release-index` על כל הספרייה —
# ‏118 דקות מול 12 דקות לאותה חבילה בלי האינדקס (ריצה 34779834547), ושני jobs
# נוספים המתינו לה. האינדקס תלוי רק ב-seforim.db ובמנוע החיפוש, ולכן הוא נבנה
# פעם אחת אחרי שחרור הספרייה (ראה build-library-index.yml שם) ונשמר על אותו
# release. כאן רק מורידים אותו ומאמתים שהוא שייך בדיוק לבנייה הזאת.
set -euo pipefail

usage='usage: fetch_prebuilt_library_index.sh <index-dir> <seforim.db.zst> <talmud_bavli_latest.tar.zst> <pubspec.lock>'
index_dir=${1:?$usage}
database_archive=${2:?$usage}
talmud_archive=${3:?$usage}
pubspec_lock=${4:?$usage}

# The same release the database itself is taken from. Overridable so the
# packaging test can serve a fixture instead of the network.
base_url=${PREBUILT_LIBRARY_INDEX_BASE_URL:-https://github.com/Otzaria/SeforimLibrary/releases/latest/download}
provenance_name=otzaria-library-index.provenance.json
archive_name=otzaria-library-index.tar.zst
manifest_name="$archive_name.manifest.json"

fail() { echo "::error::$*" >&2; exit 1; }

[ -f "$database_archive" ] || fail "database archive not found: $database_archive"
[ -f "$talmud_archive" ] || fail "Talmud Bavli archive not found: $talmud_archive"
[ -f "$pubspec_lock" ] || fail "pubspec.lock not found: $pubspec_lock"
[ ! -e "$index_dir" ] || fail "index directory must not exist yet: $index_dir"

# Beside the target, never in /tmp: the parts, the reassembled archive and the
# expanded index are several GiB each, and a `mv` out of /tmp onto the workspace
# volume would copy the whole tree a second time.
mkdir -p "$(dirname "$index_dir")"
work=$(mktemp -d "$(dirname "$index_dir")/.prebuilt-index.XXXXXX")
trap 'rm -rf "$work"' EXIT

fetch() { # fetch <name>
  curl -fsSL --retry 3 --retry-delay 5 -o "$work/$1" "$base_url/$1" \
    || fail "cannot download $1 from $base_url — has build-library-index.yml run for this database release yet?"
}

hash_file() { sha256sum "$1" | awk '{print $1}'; }
hash_stdin() { sha256sum | awk '{print $1}'; }

fetch "$provenance_name"
read_provenance() { # read_provenance <jq-path>
  jq -er "$1" "$work/$provenance_name" \
    || fail "$provenance_name has no $1 — it was written by an older build-library-index.yml"
}

schema=$(read_provenance '.schemaVersion')
[ "$schema" = 1 ] || fail "$provenance_name is schemaVersion $schema; this build reads 1"

library_tag=$(read_provenance '.libraryReleaseTag')

# ‏1. האינדקס נבנה בדיוק מה-DB שנארז כאן. seforim.db.zst מגיע מ-
# releases/latest/download, ו-"latest" עלול להתחלף בין שתי ההורדות — ההשוואה
# הזו היא מה שהופך את הזוג לאטומי.
expected_database=$(read_provenance '.seforimDbZstSha256')
actual_database=$(hash_file "$database_archive")
[ "$expected_database" = "$actual_database" ] || fail \
  "the stored index was built from seforim.db.zst $expected_database (release $library_tag) but this build packages $actual_database — rerun build-library-index.yml in Otzaria/SeforimLibrary for the current database release"

# ‏2. אותו מנוע חיפוש. סכמת האינדקס נקבעת ע"י otzaria_search_engine, ואינדקס
# שנבנה במנוע אחר היה מגיע למשתמש כאינדקס שהאפליקציה דוחה ובונה מחדש.
expected_engine=$(read_provenance '.searchEngineVersion')
actual_engine=$(awk '
  $1 == "otzaria_search_engine:" { found = 1; next }
  found && $1 == "version:" { gsub(/"/, "", $2); print $2; exit }
' "$pubspec_lock")
[ -n "$actual_engine" ] || fail "pubspec.lock pins no otzaria_search_engine version"
[ "$expected_engine" = "$actual_engine" ] || fail \
  "the stored index was built with otzaria_search_engine $expected_engine but this build resolves $actual_engine — rerun build-library-index.yml in Otzaria/SeforimLibrary with otzaria_run_id set to a build of this revision"

# ‏3. אותה קבוצת כרכי תלמוד. הכרכים אינם מאונדקסים, אבל הם יושבים בעץ הקטלוג
# ולכן קובעים את catalogueOrder — החצי העליון של כל מזהה מסמך. סט אחר מזיז את
# הסדר של כמעט כל הספרייה מול מה שהאפליקציה תחשב אצל המשתמש, והבדיקה שבאפליקציה
# משווה רק מספר רוויזיה ולכן לא הייתה תופסת זאת.
#
# ההשוואה היא על **שמות** הכרכים ולא על בתי הארכיון:
# ‏_addBundledTalmudBavliPdfBooksToCategory גוזר כל כותרת ב-getTitleFromPath
# וממקם אותה ליד ספר הטקסט בעל אותה כותרת. סריקה מחודשת של אותן מסכתות באיכות
# אחרת משנה כל בית בארכיון ואינה משנה דבר בסדר — ולכן אסור לה להפיל בנייה.
volume_names() { # volume_names <talmud tar.zst>  — חייב להיות זהה לצד הבונה
  zstd -d -c "$1" | tar -tf - | sed 's#.*/##' | grep -i '\.pdf$' | LC_ALL=C sort -u
}
expected_volumes_digest=$(read_provenance '.talmudVolumesDigest')
actual_volumes_digest=$(volume_names "$talmud_archive" | hash_stdin)
[ "$expected_volumes_digest" = "$actual_volumes_digest" ] || fail \
  "the stored index was built against a different set of bundled Talmud volumes ($(read_provenance '.talmudVolumes') of them, name-set $expected_volumes_digest; this build packages name-set $actual_volumes_digest) — rerun build-library-index.yml in Otzaria/SeforimLibrary so the catalogue order matches"

echo "Prebuilt index: release $library_tag, engine $expected_engine, $(jq -r '.catalogueBooks // "an unreported number of"' "$work/$provenance_name") books in the catalogue"

fetch "$manifest_name"
parts=$(jq -er '.parts[].name' "$work/$manifest_name") \
  || fail "$manifest_name lists no parts"
[ -n "$parts" ] || fail "$manifest_name lists no parts"
while IFS= read -r part; do
  [ "$part" = "$(basename "$part")" ] || fail "unsafe part name in manifest: $part"
  fetch "$part"
done <<< "$parts"

# assemble_split_asset.sh verifies every part and the reassembled archive
# against the manifest; this only pins the manifest itself to the provenance,
# so a manifest swapped for another release cannot pass.
bash "$(dirname "$0")/assemble_split_asset.sh" "$work/$manifest_name"
expected_archive=$(read_provenance '.indexArchiveSha256')
actual_archive=$(hash_file "$work/$archive_name")
[ "$expected_archive" = "$actual_archive" ] || fail \
  "$archive_name hashes $actual_archive but $provenance_name records $expected_archive"

mkdir -p "$work/extract"
# The parts are no longer needed and are the same size again as the archive.
rm -f "$work/$archive_name".part-*
zstd -d -c "$work/$archive_name" | tar -C "$work/extract" -xf -
rm -f "$work/$archive_name"
[ -d "$work/extract/index" ] || fail "$archive_name does not contain an index/ directory"
mv "$work/extract/index" "$index_dir"
[ -n "$(find "$index_dir" -mindepth 1 -maxdepth 1 -print -quit)" ] \
  || fail "the extracted index is empty"
echo "Prebuilt index installed at $index_dir ($(du -sh "$index_dir" | cut -f1))"
