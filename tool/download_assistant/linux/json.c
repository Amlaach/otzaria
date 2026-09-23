#include "json.h"

#include <string.h>

#include "otz_common.h"

#define MAX_DEPTH 64

typedef struct {
  const char *start;
  const char *p;
  const char *end;
  int depth;
  GError **error;
} Parser;

static OtzJson *parse_value(Parser *ps);

static void fail(Parser *ps, const char *what) {
  if (ps->error != NULL && *ps->error == NULL)
    g_set_error(ps->error, OTZ_ERROR, OTZ_ERROR_PARSE, "JSON: %s at offset %ld",
                what, (long)(ps->p - ps->start));
}

static void skip_ws(Parser *ps) {
  while (ps->p < ps->end &&
         (*ps->p == ' ' || *ps->p == '\t' || *ps->p == '\n' || *ps->p == '\r'))
    ps->p++;
}

static OtzJson *new_value(OtzJsonType type) {
  OtzJson *value = g_new0(OtzJson, 1);
  value->type = type;
  return value;
}

void otz_json_free(OtzJson *value) {
  if (value == NULL) return;
  g_free(value->string);
  if (value->items != NULL) g_ptr_array_unref(value->items);
  if (value->keys != NULL) g_ptr_array_unref(value->keys);
  g_free(value);
}

static gboolean read_hex4(Parser *ps, gunichar *out) {
  if (ps->end - ps->p < 4) {
    fail(ps, "truncated \\u escape");
    return FALSE;
  }
  gunichar value = 0;
  for (int i = 0; i < 4; i++) {
    int digit = g_ascii_xdigit_value(ps->p[i]);
    if (digit < 0) {
      fail(ps, "bad \\u escape");
      return FALSE;
    }
    value = (value << 4) | (gunichar)digit;
  }
  ps->p += 4;
  *out = value;
  return TRUE;
}

static char *parse_string(Parser *ps) {
  ps->p++; /* opening quote */
  GString *out = g_string_new(NULL);
  for (;;) {
    if (ps->p >= ps->end) {
      fail(ps, "unterminated string");
      goto error;
    }
    unsigned char c = (unsigned char)*ps->p;
    if (c == '"') {
      ps->p++;
      return g_string_free(out, FALSE);
    }
    if (c < 0x20) {
      fail(ps, "control character in string");
      goto error;
    }
    if (c != '\\') {
      const char *run = ps->p;
      while (ps->p < ps->end && *ps->p != '"' && *ps->p != '\\' &&
             (unsigned char)*ps->p >= 0x20)
        ps->p++;
      g_string_append_len(out, run, ps->p - run);
      continue;
    }
    ps->p++;
    if (ps->p >= ps->end) {
      fail(ps, "unterminated escape");
      goto error;
    }
    char escape = *ps->p++;
    switch (escape) {
      case '"': g_string_append_c(out, '"'); break;
      case '\\': g_string_append_c(out, '\\'); break;
      case '/': g_string_append_c(out, '/'); break;
      case 'b': g_string_append_c(out, '\b'); break;
      case 'f': g_string_append_c(out, '\f'); break;
      case 'n': g_string_append_c(out, '\n'); break;
      case 'r': g_string_append_c(out, '\r'); break;
      case 't': g_string_append_c(out, '\t'); break;
      case 'u': {
        gunichar u;
        if (!read_hex4(ps, &u)) goto error;
        if (u >= 0xD800 && u <= 0xDBFF) {
          gunichar low;
          if (ps->end - ps->p < 2 || ps->p[0] != '\\' || ps->p[1] != 'u') {
            fail(ps, "lone high surrogate");
            goto error;
          }
          ps->p += 2;
          if (!read_hex4(ps, &low)) goto error;
          if (low < 0xDC00 || low > 0xDFFF) {
            fail(ps, "bad low surrogate");
            goto error;
          }
          u = 0x10000 + ((u - 0xD800) << 10) + (low - 0xDC00);
        } else if (u >= 0xDC00 && u <= 0xDFFF) {
          fail(ps, "lone low surrogate");
          goto error;
        } else if (u == 0) {
          fail(ps, "NUL in string");
          goto error;
        }
        g_string_append_unichar(out, u);
        break;
      }
      default:
        fail(ps, "bad escape");
        goto error;
    }
  }
error:
  g_string_free(out, TRUE);
  return NULL;
}

static gboolean is_digit(Parser *ps) {
  return ps->p < ps->end && *ps->p >= '0' && *ps->p <= '9';
}

static OtzJson *parse_number(Parser *ps) {
  const char *begin = ps->p;
  gboolean integral = TRUE;
  if (ps->p < ps->end && *ps->p == '-') ps->p++;
  if (ps->p < ps->end && *ps->p == '0') {
    ps->p++;
  } else if (is_digit(ps)) {
    while (is_digit(ps)) ps->p++;
  } else {
    fail(ps, "bad number");
    return NULL;
  }
  if (ps->p < ps->end && *ps->p == '.') {
    ps->p++;
    integral = FALSE;
    if (!is_digit(ps)) {
      fail(ps, "bad fraction");
      return NULL;
    }
    while (is_digit(ps)) ps->p++;
  }
  if (ps->p < ps->end && (*ps->p == 'e' || *ps->p == 'E')) {
    ps->p++;
    integral = FALSE;
    if (ps->p < ps->end && (*ps->p == '+' || *ps->p == '-')) ps->p++;
    if (!is_digit(ps)) {
      fail(ps, "bad exponent");
      return NULL;
    }
    while (is_digit(ps)) ps->p++;
  }
  g_autofree char *text = g_strndup(begin, ps->p - begin);
  gint64 integer;
  if (integral && g_ascii_string_to_signed(text, 10, G_MININT64, G_MAXINT64,
                                           &integer, NULL)) {
    OtzJson *value = new_value(OTZ_JSON_INT);
    value->integer = integer;
    value->number = (double)integer;
    return value;
  }
  OtzJson *value = new_value(OTZ_JSON_DOUBLE);
  value->number = g_ascii_strtod(text, NULL);
  return value;
}

static gboolean match_literal(Parser *ps, const char *word) {
  gsize length = strlen(word);
  if ((gsize)(ps->end - ps->p) < length || memcmp(ps->p, word, length) != 0) {
    fail(ps, "bad literal");
    return FALSE;
  }
  ps->p += length;
  return TRUE;
}

static OtzJson *parse_container(Parser *ps, gboolean object) {
  if (++ps->depth > MAX_DEPTH) {
    fail(ps, "nesting too deep");
    return NULL;
  }
  char close = object ? '}' : ']';
  OtzJson *value = new_value(object ? OTZ_JSON_OBJECT : OTZ_JSON_ARRAY);
  value->items = g_ptr_array_new_with_free_func((GDestroyNotify)otz_json_free);
  if (object) value->keys = g_ptr_array_new_with_free_func(g_free);
  ps->p++;
  skip_ws(ps);
  if (ps->p < ps->end && *ps->p == close) {
    ps->p++;
    ps->depth--;
    return value;
  }
  for (;;) {
    skip_ws(ps);
    if (object) {
      if (ps->p >= ps->end || *ps->p != '"') {
        fail(ps, "expected key");
        goto error;
      }
      char *key = parse_string(ps);
      if (key == NULL) goto error;
      g_ptr_array_add(value->keys, key);
      skip_ws(ps);
      if (ps->p >= ps->end || *ps->p != ':') {
        fail(ps, "expected ':'");
        goto error;
      }
      ps->p++;
    }
    OtzJson *item = parse_value(ps);
    if (item == NULL) goto error;
    g_ptr_array_add(value->items, item);
    skip_ws(ps);
    if (ps->p < ps->end && *ps->p == ',') {
      ps->p++;
      continue;
    }
    if (ps->p < ps->end && *ps->p == close) {
      ps->p++;
      ps->depth--;
      return value;
    }
    fail(ps, object ? "expected ',' or '}'" : "expected ',' or ']'");
    goto error;
  }
error:
  otz_json_free(value);
  return NULL;
}

static OtzJson *parse_value(Parser *ps) {
  skip_ws(ps);
  if (ps->p >= ps->end) {
    fail(ps, "unexpected end");
    return NULL;
  }
  switch (*ps->p) {
    case '{': return parse_container(ps, TRUE);
    case '[': return parse_container(ps, FALSE);
    case '"': {
      char *text = parse_string(ps);
      if (text == NULL) return NULL;
      OtzJson *value = new_value(OTZ_JSON_STRING);
      value->string = text;
      return value;
    }
    case 't':
    case 'f': {
      gboolean truth = *ps->p == 't';
      if (!match_literal(ps, truth ? "true" : "false")) return NULL;
      OtzJson *value = new_value(OTZ_JSON_BOOL);
      value->boolean = truth;
      return value;
    }
    case 'n':
      if (!match_literal(ps, "null")) return NULL;
      return new_value(OTZ_JSON_NULL);
    default:
      return parse_number(ps);
  }
}

OtzJson *otz_json_parse(const char *data, gsize length, GError **error) {
  if (!g_utf8_validate(data, (gssize)length, NULL)) {
    g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PARSE,
                        "JSON: not valid UTF-8");
    return NULL;
  }
  Parser ps = {data, data, data + length, 0, error};
  if (length >= 3 && memcmp(data, "\xEF\xBB\xBF", 3) == 0) ps.p += 3;
  OtzJson *value = parse_value(&ps);
  if (value == NULL) return NULL;
  skip_ws(&ps);
  if (ps.p != ps.end) {
    fail(&ps, "trailing data");
    otz_json_free(value);
    return NULL;
  }
  return value;
}

const OtzJson *otz_json_get(const OtzJson *object, const char *key) {
  if (object == NULL || object->type != OTZ_JSON_OBJECT) return NULL;
  for (guint i = object->keys->len; i > 0; i--) {
    if (strcmp(g_ptr_array_index(object->keys, i - 1), key) == 0)
      return g_ptr_array_index(object->items, i - 1);
  }
  return NULL;
}

const char *otz_json_get_string(const OtzJson *object, const char *key) {
  const OtzJson *value = otz_json_get(object, key);
  return value != NULL && value->type == OTZ_JSON_STRING ? value->string : NULL;
}

gboolean otz_json_get_int(const OtzJson *object, const char *key, gint64 *out) {
  const OtzJson *value = otz_json_get(object, key);
  if (value == NULL || value->type != OTZ_JSON_INT) return FALSE;
  *out = value->integer;
  return TRUE;
}

guint otz_json_array_length(const OtzJson *array) {
  return array != NULL && array->type == OTZ_JSON_ARRAY ? array->items->len : 0;
}

const OtzJson *otz_json_array_get(const OtzJson *array, guint index) {
  if (index >= otz_json_array_length(array)) return NULL;
  return g_ptr_array_index(array->items, index);
}
