#include "http.h"

#include <string.h>

#include "otz_common.h"

#define MAX_REDIRECTS 5
#define MAX_HEADER_LINE 8192
#define MAX_HEADERS 200
#define SOCKET_TIMEOUT_SECONDS 30
#define STREAM_BUFFER_SIZE (256 * 1024)

static const char *const allowed_hosts[] = {
    "github.com",
    "api.github.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
    NULL,
};

struct OtzHttpResponse {
  GSocketClient *client;
  GSocketConnection *connection;
  GDataInputStream *in;
  OtzHttpHead head;
  OtzHttpBody body;
};

void otz_http_head_clear(OtzHttpHead *head) {
  g_clear_pointer(&head->location, g_free);
  g_clear_pointer(&head->content_range, g_free);
  head->status = 0;
  head->content_length = -1;
  head->chunked = FALSE;
}

/* Reads one line out of the stream's buffer, refusing it once it passes
 * MAX_HEADER_LINE without a newline — a hostile server cannot make us buffer
 * an unbounded header. */
static char *read_line(GDataInputStream *in, GCancellable *cancellable,
                       GError **error) {
  GBufferedInputStream *buffered = G_BUFFERED_INPUT_STREAM(in);
  if (g_buffered_input_stream_get_buffer_size(buffered) < 2 * MAX_HEADER_LINE)
    g_buffered_input_stream_set_buffer_size(buffered, 2 * MAX_HEADER_LINE);
  for (;;) {
    gsize available = 0;
    const char *data = g_buffered_input_stream_peek_buffer(buffered, &available);
    gsize scan = MIN(available, (gsize)MAX_HEADER_LINE + 1);
    const char *newline = scan > 0 ? memchr(data, '\n', scan) : NULL;
    if (newline != NULL) {
      gsize length = (gsize)(newline - data);
      if (memchr(data, '\0', length) != NULL) {
        g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                            "malformed header line");
        return NULL;
      }
      /* A CR before the LF belongs to the line ending. */
      char *line = g_strndup(data, length > 0 && data[length - 1] == '\r'
                                       ? length - 1
                                       : length);
      if (g_input_stream_skip(G_INPUT_STREAM(in), length + 1, cancellable,
                              error) < 0) {
        g_free(line);
        return NULL;
      }
      return line;
    }
    if (available > MAX_HEADER_LINE) {
      g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                          "header line too long");
      return NULL;
    }
    gssize filled = g_buffered_input_stream_fill(buffered, -1, cancellable, error);
    if (filled < 0) return NULL;
    if (filled == 0) {
      g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_NETWORK,
                          "connection closed in the middle of a reply");
      return NULL;
    }
  }
}

static gboolean parse_decimal(const char *text, gint64 *out) {
  if (text == NULL || *text == '\0') return FALSE;
  for (const char *p = text; *p; p++) {
    if (!g_ascii_isdigit(*p)) return FALSE;
  }
  guint64 value;
  if (!g_ascii_string_to_unsigned(text, 10, 0, G_MAXINT64, &value, NULL))
    return FALSE;
  *out = (gint64)value;
  return TRUE;
}

gboolean otz_http_read_head(GDataInputStream *in, OtzHttpHead *head,
                            GCancellable *cancellable, GError **error) {
  otz_http_head_clear(head);
  for (;;) {
    g_autofree char *status_line = read_line(in, cancellable, error);
    if (status_line == NULL) return FALSE;
    if (!g_str_has_prefix(status_line, "HTTP/1.") || strlen(status_line) < 12 ||
        status_line[8] != ' ' || !g_ascii_isdigit(status_line[9]) ||
        !g_ascii_isdigit(status_line[10]) || !g_ascii_isdigit(status_line[11]) ||
        (status_line[12] != '\0' && status_line[12] != ' ')) {
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL, "bad status line: %.80s",
                  status_line);
      return FALSE;
    }
    head->status = (guint)((status_line[9] - '0') * 100 +
                           (status_line[10] - '0') * 10 + (status_line[11] - '0'));

    int count = 0;
    for (;;) {
      g_autofree char *line = read_line(in, cancellable, error);
      if (line == NULL) return FALSE;
      if (*line == '\0') break;
      if (++count > MAX_HEADERS) {
        g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                            "too many headers");
        return FALSE;
      }
      char *colon = strchr(line, ':');
      if (colon == NULL || colon == line) {
        g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                            "malformed header");
        return FALSE;
      }
      *colon = '\0';
      const char *name = line;
      char *value = g_strstrip(colon + 1);
      if (g_ascii_strcasecmp(name, "Content-Length") == 0) {
        gint64 length;
        if (!parse_decimal(value, &length) ||
            (head->content_length >= 0 && head->content_length != length)) {
          g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                              "bad Content-Length");
          return FALSE;
        }
        head->content_length = length;
      } else if (g_ascii_strcasecmp(name, "Transfer-Encoding") == 0) {
        /* chunked must be the last coding; anything else is unsupported. */
        g_auto(GStrv) codings = g_strsplit(value, ",", -1);
        guint n = g_strv_length(codings);
        for (guint i = 0; i < n; i++) g_strstrip(codings[i]);
        if (n == 0 || g_ascii_strcasecmp(codings[n - 1], "chunked") != 0) {
          g_set_error(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                      "unsupported Transfer-Encoding: %.60s", value);
          return FALSE;
        }
        head->chunked = TRUE;
      } else if (g_ascii_strcasecmp(name, "Location") == 0) {
        g_free(head->location);
        head->location = g_strdup(value);
      } else if (g_ascii_strcasecmp(name, "Content-Range") == 0) {
        g_free(head->content_range);
        head->content_range = g_strdup(value);
      }
    }
    /* 1xx replies precede the real one. */
    if (head->status >= 200) return TRUE;
    otz_http_head_clear(head);
  }
}

void otz_http_body_init(OtzHttpBody *body, GDataInputStream *in,
                        const OtzHttpHead *head) {
  body->in = G_INPUT_STREAM(in);
  body->chunked = head->chunked;
  body->remaining = head->chunked ? -1 : head->content_length;
  body->chunk_left = -1;
  body->done = FALSE;
  if (head->status == 204 || head->status == 304 ||
      (!head->chunked && head->content_length == 0))
    body->done = TRUE;
}

static gboolean read_chunk_size(OtzHttpBody *body, GCancellable *cancellable,
                                GError **error) {
  GDataInputStream *in = G_DATA_INPUT_STREAM(body->in);
  if (body->chunk_left == 0) {
    /* CRLF that closes the previous chunk's data. */
    g_autofree char *end = read_line(in, cancellable, error);
    if (end == NULL) return FALSE;
    if (*end != '\0') {
      g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                          "chunk not followed by CRLF");
      return FALSE;
    }
  }
  g_autofree char *line = read_line(in, cancellable, error);
  if (line == NULL) return FALSE;
  char *extension = strchr(line, ';');
  if (extension != NULL) *extension = '\0';
  g_strstrip(line);
  guint64 size;
  if (*line == '\0' || strlen(line) > 15 ||
      !g_ascii_string_to_unsigned(line, 16, 0, G_MAXINT64, &size, NULL)) {
    g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                        "bad chunk size");
    return FALSE;
  }
  if (size == 0) {
    for (;;) { /* trailers */
      g_autofree char *trailer = read_line(in, cancellable, error);
      if (trailer == NULL) return FALSE;
      if (*trailer == '\0') break;
    }
    body->done = TRUE;
  }
  body->chunk_left = (gint64)size;
  return TRUE;
}

gssize otz_http_body_read(OtzHttpBody *body, void *buffer, gsize count,
                          GCancellable *cancellable, GError **error) {
  if (body->done || count == 0) return 0;
  gsize want = count;
  if (body->chunked) {
    if (body->chunk_left <= 0) {
      if (!read_chunk_size(body, cancellable, error)) return -1;
      if (body->done) return 0;
    }
    want = MIN(want, (gsize)body->chunk_left);
  } else if (body->remaining >= 0) {
    want = MIN(want, (gsize)body->remaining);
  }
  gssize n = g_input_stream_read(body->in, buffer, want, cancellable, error);
  if (n < 0) return -1;
  if (n == 0) {
    if (body->chunked || body->remaining > 0) {
      g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_NETWORK,
                          "connection closed before the end of the body");
      return -1;
    }
    body->done = TRUE;
    return 0;
  }
  if (body->chunked) {
    body->chunk_left -= n;
  } else if (body->remaining >= 0) {
    body->remaining -= n;
    if (body->remaining == 0) body->done = TRUE;
  }
  return n;
}

gboolean otz_http_parse_content_range(const char *value, gint64 *start,
                                      gint64 *end, gint64 *total) {
  if (value == NULL || g_ascii_strncasecmp(value, "bytes ", 6) != 0)
    return FALSE;
  const char *p = value + 6;
  while (*p == ' ') p++;
  const char *dash = strchr(p, '-');
  const char *slash = dash != NULL ? strchr(dash, '/') : NULL;
  if (dash == NULL || slash == NULL) return FALSE;
  g_autofree char *a = g_strndup(p, dash - p);
  g_autofree char *b = g_strndup(dash + 1, slash - dash - 1);
  g_autofree char *c = g_strdup(slash + 1);
  g_strstrip(c);
  if (!parse_decimal(a, start) || !parse_decimal(b, end) ||
      !parse_decimal(c, total))
    return FALSE;
  return *start <= *end && *end < *total;
}

static gboolean check_uri(GUri *uri, GError **error) {
  const char *scheme = g_uri_get_scheme(uri);
  const char *host = g_uri_get_host(uri);
  if (scheme == NULL || g_ascii_strcasecmp(scheme, "https") != 0) {
    g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_BLOCKED,
                        "only https is allowed");
    return FALSE;
  }
  if (g_uri_get_userinfo(uri) != NULL ||
      (g_uri_get_port(uri) != -1 && g_uri_get_port(uri) != 443)) {
    g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_BLOCKED,
                        "unexpected userinfo or port");
    return FALSE;
  }
  gboolean known = FALSE;
  for (gsize i = 0; host != NULL && allowed_hosts[i] != NULL; i++) {
    if (g_ascii_strcasecmp(host, allowed_hosts[i]) == 0) known = TRUE;
  }
  if (!known) {
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_BLOCKED, "host not allowed: %s",
                host != NULL ? host : "(none)");
    return FALSE;
  }
  if (g_ascii_strcasecmp(host, "github.com") == 0) {
    g_autofree char *prefix = g_strdup_printf("/%s/", otz_allowed_owner());
    if (!g_str_has_prefix(g_uri_get_path(uri), prefix)) {
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_BLOCKED,
                  "path outside the organization: %s", g_uri_get_path(uri));
      return FALSE;
    }
  }
  return TRUE;
}

gboolean otz_http_check_url(const char *url, GError **error) {
  g_autoptr(GUri) uri = g_uri_parse(url, G_URI_FLAGS_ENCODED, error);
  if (uri == NULL) return FALSE;
  return check_uri(uri, error);
}

static char *user_agent(void) {
  const char *tag = otz_embedded_release_tag();
  return g_strdup_printf("Otzaria-Download-Assistant/%s (Linux)",
                         *tag != '\0' ? tag : "dev");
}

void otz_http_response_free(OtzHttpResponse *response) {
  if (response == NULL) return;
  otz_http_head_clear(&response->head);
  g_clear_object(&response->in);
  if (response->connection != NULL)
    g_io_stream_close(G_IO_STREAM(response->connection), NULL, NULL);
  g_clear_object(&response->connection);
  g_clear_object(&response->client);
  g_free(response);
}

static OtzHttpResponse *request_once(GUri *uri, gint64 range_from,
                                     const char *accept,
                                     GCancellable *cancellable, GError **error) {
  g_autofree char *agent = user_agent();
  OtzHttpResponse *response = g_new0(OtzHttpResponse, 1);
  response->head.content_length = -1;
  response->client = g_socket_client_new();
  g_socket_client_set_tls(response->client, TRUE);
  g_socket_client_set_timeout(response->client, SOCKET_TIMEOUT_SECONDS);
  response->connection = g_socket_client_connect_to_host(
      response->client, g_uri_get_host(uri), 443, cancellable, error);
  if (response->connection == NULL) goto fail;

  const char *path = g_uri_get_path(uri);
  const char *query = g_uri_get_query(uri);
  GString *request = g_string_new(NULL);
  g_string_append_printf(request, "GET %s%s%s HTTP/1.1\r\n",
                         *path != '\0' ? path : "/", query != NULL ? "?" : "",
                         query != NULL ? query : "");
  g_string_append_printf(request, "Host: %s\r\n", g_uri_get_host(uri));
  g_string_append_printf(request, "User-Agent: %s\r\n", agent);
  g_string_append_printf(request, "Accept: %s\r\n",
                         accept != NULL ? accept : "*/*");
  g_string_append(request, "Accept-Encoding: identity\r\n");
  if (range_from >= 0)
    g_string_append_printf(request, "Range: bytes=%" G_GINT64_FORMAT "-\r\n",
                           range_from);
  g_string_append(request, "Connection: close\r\n\r\n");
  GOutputStream *out =
      g_io_stream_get_output_stream(G_IO_STREAM(response->connection));
  gboolean sent = g_output_stream_write_all(out, request->str, request->len,
                                            NULL, cancellable, error);
  g_string_free(request, TRUE);
  if (!sent) goto fail;

  response->in = g_data_input_stream_new(
      g_io_stream_get_input_stream(G_IO_STREAM(response->connection)));
  g_buffered_input_stream_set_buffer_size(G_BUFFERED_INPUT_STREAM(response->in),
                                          STREAM_BUFFER_SIZE);
  g_data_input_stream_set_newline_type(response->in,
                                       G_DATA_STREAM_NEWLINE_TYPE_LF);
  if (!otz_http_read_head(response->in, &response->head, cancellable, error))
    goto fail;
  otz_http_body_init(&response->body, response->in, &response->head);
  return response;

fail:
  otz_http_response_free(response);
  return NULL;
}

OtzHttpResponse *otz_http_get(const char *url, gint64 range_from,
                              const char *accept, GCancellable *cancellable,
                              GError **error) {
  g_autoptr(GUri) uri = g_uri_parse(url, G_URI_FLAGS_ENCODED, error);
  if (uri == NULL) return NULL;
  for (int hop = 0;; hop++) {
    if (!check_uri(uri, error)) return NULL;
    OtzHttpResponse *response =
        request_once(uri, range_from, accept, cancellable, error);
    if (response == NULL) return NULL;
    guint status = response->head.status;
    gboolean redirect = status == 301 || status == 302 || status == 303 ||
                        status == 307 || status == 308;
    if (!redirect) return response;
    if (hop >= MAX_REDIRECTS || response->head.location == NULL) {
      g_set_error_literal(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                          "too many redirects or redirect without Location");
      otz_http_response_free(response);
      return NULL;
    }
    GUri *next = g_uri_parse_relative(uri, response->head.location,
                                      G_URI_FLAGS_ENCODED, error);
    otz_http_response_free(response);
    if (next == NULL) return NULL;
    g_uri_unref(uri);
    uri = next;
  }
}

const OtzHttpHead *otz_http_response_head(OtzHttpResponse *response) {
  return &response->head;
}

gssize otz_http_response_read(OtzHttpResponse *response, void *buffer,
                              gsize count, GCancellable *cancellable,
                              GError **error) {
  return otz_http_body_read(&response->body, buffer, count, cancellable, error);
}

GBytes *otz_http_fetch(const char *url, const char *accept, gsize max_size,
                       GCancellable *cancellable, GError **error) {
  g_autoptr(OtzHttpResponse) response =
      otz_http_get(url, -1, accept, cancellable, error);
  if (response == NULL) return NULL;
  guint status = response->head.status;
  if (status != 200) {
    g_set_error(error, OTZ_ERROR,
                status >= 500                    ? OTZ_ERROR_HTTP_SERVER
                : status == 403 || status == 429 ? OTZ_ERROR_RATE_LIMITED
                                                 : OTZ_ERROR_HTTP,
                "HTTP %u from %s", status, url);
    return NULL;
  }
  GByteArray *data = g_byte_array_new();
  guint8 buffer[65536];
  for (;;) {
    gssize n = otz_http_response_read(response, buffer, sizeof buffer,
                                      cancellable, error);
    if (n < 0) {
      g_byte_array_unref(data);
      return NULL;
    }
    if (n == 0) break;
    if (data->len + (gsize)n > max_size) {
      g_byte_array_unref(data);
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_PROTOCOL,
                  "reply larger than %" G_GSIZE_FORMAT " bytes", max_size);
      return NULL;
    }
    g_byte_array_append(data, buffer, (guint)n);
  }
  return g_byte_array_free_to_bytes(data);
}
