/* Picking the release and loading its manifest ("מקור ההורדה והתג"). */
#pragma once

#include <gio/gio.h>

#include "manifest.h"

/* 1 if a > b, -1 if a < b, 0 if equal — on the X.Y.Z part only ("+build" and a
 * leading "v" are ignored: run numbers are not a version order). */
int otz_compare_versions(const char *a, const char *b);

/* The latest release wins only when it is a higher version than the embedded
 * tag; with no embedded tag (a local build) it is always the latest. */
char *otz_pick_release_tag(const char *embedded, const char *latest);

/* Resolves the tag once, finds the *release-manifest.json asset in it and loads
 * the manifest. On failure *user_message is the Hebrew text to show. */
OtzManifest *otz_load_release_manifest(char **pinned_tag,
                                       const char **user_message,
                                       GCancellable *cancellable,
                                       GError **error);

#define OTZ_DIRECT_MANIFEST_NAME "otzaria-release-manifest.json"

/* The manifest's download URL for a tag, "+" percent-encoded. */
char *otz_direct_manifest_url(const char *tag);
/* TRUE when an API failure (403/429) should fall back to that URL: only with
 * an embedded tag, and then the "is latest higher" check is skipped. */
gboolean otz_api_failure_uses_direct_manifest(const GError *api_error,
                                              const char *embedded_tag);

/* Dev only (--dev-manifest): a local manifest file instead of the network. */
OtzManifest *otz_load_manifest_file(const char *path, GError **error);
