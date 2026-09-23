#include "release.h"

#include <string.h>

#include "http.h"
#include "json.h"
#include "otz_common.h"

#define MAX_API_REPLY (16 * 1024 * 1024)
#define MAX_MANIFEST (16 * 1024 * 1024)
#define API_ACCEPT "application/vnd.github+json"

static char *version_part(const char *tag) {
  char *result = g_strstrip(g_strdup(tag != NULL ? tag : ""));
  char *plus = strchr(result, '+');
  if (plus != NULL) *plus = '\0';
  if (result[0] == 'v' || result[0] == 'V') memmove(result, result + 1, strlen(result));
  return result;
}

static gint64 segment_value(const char *text) {
  gint64 value;
  return g_ascii_string_to_signed(text, 10, G_MININT64, G_MAXINT64, &value, NULL)
             ? value
             : 0;
}

int otz_compare_versions(const char *a, const char *b) {
  g_autofree char *va = version_part(a);
  g_autofree char *vb = version_part(b);
  g_auto(GStrv) pa = g_strsplit(va, ".", -1);
  g_auto(GStrv) pb = g_strsplit(vb, ".", -1);
  /* Empty segments are skipped, as StringSplitEx(stExcludeEmpty) does in Inno. */
  GPtrArray *sa = g_ptr_array_new();
  GPtrArray *sb = g_ptr_array_new();
  for (gsize i = 0; pa[i] != NULL; i++)
    if (*pa[i] != '\0') g_ptr_array_add(sa, pa[i]);
  for (gsize i = 0; pb[i] != NULL; i++)
    if (*pb[i] != '\0') g_ptr_array_add(sb, pb[i]);
  int result = 0;
  guint n = MAX(sa->len, sb->len);
  for (guint i = 0; i < n && result == 0; i++) {
    gint64 x = i < sa->len ? segment_value(g_ptr_array_index(sa, i)) : 0;
    gint64 y = i < sb->len ? segment_value(g_ptr_array_index(sb, i)) : 0;
    result = x > y ? 1 : (x < y ? -1 : 0);
  }
  g_ptr_array_unref(sa);
  g_ptr_array_unref(sb);
  return result;
}

char *otz_pick_release_tag(const char *embedded, const char *latest) {
  embedded = embedded != NULL ? embedded : "";
  latest = latest != NULL ? latest : "";
  if (*embedded == '\0') return g_strdup(latest);
  if (*latest != '\0' && otz_compare_versions(latest, embedded) > 0)
    return g_strdup(latest);
  return g_strdup(embedded);
}

static char *api_url(const char *path) {
  return g_strdup_printf("https://api.github.com/repos/%s/otzaria/releases/%s",
                         otz_allowed_owner(), path);
}

static OtzJson *fetch_json(const char *url, GCancellable *cancellable,
                           GError **error) {
  g_autoptr(GBytes) bytes =
      otz_http_fetch(url, API_ACCEPT, MAX_API_REPLY, cancellable, error);
  if (bytes == NULL) return NULL;
  gsize size;
  const char *data = g_bytes_get_data(bytes, &size);
  return otz_json_parse(data, size, error);
}

char *otz_direct_manifest_url(const char *tag) {
  g_autofree char *escaped = g_uri_escape_string(tag, NULL, FALSE);
  return g_strdup_printf("https://github.com/%s/otzaria/releases/download/%s/%s",
                         otz_allowed_owner(), escaped, OTZ_DIRECT_MANIFEST_NAME);
}

gboolean otz_api_failure_uses_direct_manifest(const GError *api_error,
                                              const char *embedded_tag) {
  return embedded_tag != NULL && *embedded_tag != '\0' &&
         otz_is_safe_token(embedded_tag) && api_error != NULL &&
         !g_error_matches(api_error, G_IO_ERROR, G_IO_ERROR_CANCELLED);
}

static OtzManifest *fetch_manifest(const char *url, GCancellable *cancellable,
                                   GError **error) {
  g_autoptr(GBytes) bytes =
      otz_http_fetch(url, NULL, MAX_MANIFEST, cancellable, error);
  if (bytes == NULL) return NULL;
  gsize size;
  const char *data = g_bytes_get_data(bytes, &size);
  return otz_manifest_parse(data, size, error);
}

/* The embedded tag locates the manifest even when the API is unavailable. */
static OtzManifest *load_direct(const char *tag, const GError *api_error,
                                char **pinned_tag, const char **user_message,
                                GCancellable *cancellable, GError **error) {
  g_message("GitHub API unavailable (%s); using the embedded tag %s without "
            "checking for a newer release",
            api_error->message, tag);
  *user_message = "לא ניתן לקרוא את רשימת הקבצים של אוצריא.";
  g_autofree char *url = otz_direct_manifest_url(tag);
  OtzManifest *manifest = fetch_manifest(url, cancellable, error);
  if (manifest != NULL) *pinned_tag = g_strdup(tag);
  return manifest;
}

OtzManifest *otz_load_release_manifest(char **pinned_tag,
                                       const char **user_message,
                                       GCancellable *cancellable,
                                       GError **error) {
  const char *embedded = otz_embedded_release_tag();
  *user_message = "לא ניתן להתחבר לאתר ההורדות של אוצריא.";
  g_autofree char *latest_url = api_url("latest");
  g_autoptr(GError) latest_error = NULL;
  g_autoptr(OtzJson) release = fetch_json(latest_url, cancellable, &latest_error);
  if (g_cancellable_set_error_if_cancelled(cancellable, error)) return NULL;
  if (release == NULL &&
      otz_api_failure_uses_direct_manifest(latest_error, embedded))
    return load_direct(embedded, latest_error, pinned_tag, user_message,
                       cancellable, error);
  const char *latest_tag = otz_json_get_string(release, "tag_name");

  g_autofree char *tag = otz_pick_release_tag(embedded, latest_tag);
  g_debug("release tag: embedded=%s latest=%s pinned=%s", embedded,
          latest_tag != NULL ? latest_tag : "", tag);
  if (*tag == '\0' || !otz_is_safe_token(tag)) {
    if (latest_error != NULL)
      g_propagate_error(error, g_steal_pointer(&latest_error));
    else
      g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PARSE,
                          "release has no usable tag_name");
    return NULL;
  }

  if (latest_tag == NULL || strcmp(tag, latest_tag) != 0) {
    /* "+" is literal in a download path, but the API route needs it encoded. */
    g_autofree char *escaped = g_uri_escape_string(tag, NULL, FALSE);
    g_autofree char *path = g_strconcat("tags/", escaped, NULL);
    g_autofree char *url = api_url(path);
    g_autoptr(GError) tag_error = NULL;
    g_clear_pointer(&release, otz_json_free);
    release = fetch_json(url, cancellable, &tag_error);
    if (release == NULL) {
      if (strcmp(tag, embedded) == 0 &&
          otz_api_failure_uses_direct_manifest(tag_error, embedded))
        return load_direct(embedded, tag_error, pinned_tag, user_message,
                           cancellable, error);
      g_propagate_error(error, g_steal_pointer(&tag_error));
      return NULL;
    }
  }

  const char *manifest_asset = NULL;
  const OtzJson *assets = otz_json_get(release, "assets");
  for (guint i = 0; i < otz_json_array_length(assets); i++) {
    const char *name = otz_json_get_string(otz_json_array_get(assets, i), "name");
    if (name != NULL && g_str_has_suffix(name, "release-manifest.json")) {
      manifest_asset = name;
      break;
    }
  }
  *user_message = "לא ניתן לקרוא את רשימת הקבצים של אוצריא.";
  if (manifest_asset == NULL || !otz_is_safe_token(manifest_asset)) {
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_PARSE,
                "release %s has no release-manifest asset", tag);
    return NULL;
  }

  g_autofree char *url =
      g_strdup_printf("https://github.com/%s/otzaria/releases/download/%s/%s",
                      otz_allowed_owner(), tag, manifest_asset);
  OtzManifest *manifest = fetch_manifest(url, cancellable, error);
  if (manifest != NULL) *pinned_tag = g_steal_pointer(&tag);
  return manifest;
}

OtzManifest *otz_load_manifest_file(const char *path, GError **error) {
  g_autofree char *data = NULL;
  gsize size;
  if (!g_file_get_contents(path, &data, &size, error)) return NULL;
  return otz_manifest_parse(data, size, error);
}
