/* Minimal JSON reader: enough for the release manifest and GitHub API replies. */
#pragma once

#include <glib.h>

typedef enum {
  OTZ_JSON_NULL,
  OTZ_JSON_BOOL,
  OTZ_JSON_INT,
  OTZ_JSON_DOUBLE,
  OTZ_JSON_STRING,
  OTZ_JSON_ARRAY,
  OTZ_JSON_OBJECT,
} OtzJsonType;

typedef struct OtzJson {
  OtzJsonType type;
  gboolean boolean;
  gint64 integer;
  double number;
  char *string;     /* UTF-8, never contains NUL */
  GPtrArray *items; /* array elements, or object values */
  GPtrArray *keys;  /* object keys, parallel to items */
} OtzJson;

OtzJson *otz_json_parse(const char *data, gsize length, GError **error);
void otz_json_free(OtzJson *value);
G_DEFINE_AUTOPTR_CLEANUP_FUNC(OtzJson, otz_json_free)

/* Object member (last one wins on duplicate keys), or NULL. */
const OtzJson *otz_json_get(const OtzJson *object, const char *key);
/* NULL unless the member exists and is a string. */
const char *otz_json_get_string(const OtzJson *object, const char *key);
/* FALSE unless the member exists and is an integer. */
gboolean otz_json_get_int(const OtzJson *object, const char *key, gint64 *out);

guint otz_json_array_length(const OtzJson *array);
const OtzJson *otz_json_array_get(const OtzJson *array, guint index);
