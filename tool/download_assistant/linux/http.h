/* Minimal HTTP/1.1 GET over GIO TLS: redirects, Range, Content-Length and
 * chunked bodies. libsoup/libcurl are not dependencies of Otzaria, and the
 * machine preparing the install is not necessarily one Otzaria runs on. */
#pragma once

#include <gio/gio.h>

typedef struct {
  guint status;
  gint64 content_length; /* -1 when absent */
  gboolean chunked;
  char *location;
  char *content_range;
} OtzHttpHead;

typedef struct {
  GInputStream *in; /* buffered: the head was read through the same stream */
  gboolean chunked;
  gint64 remaining;  /* Content-Length mode; -1 reads to EOF */
  gint64 chunk_left; /* chunked mode; -1 before the first chunk line */
  gboolean done;
} OtzHttpBody;

gboolean otz_http_read_head(GDataInputStream *in, OtzHttpHead *head,
                            GCancellable *cancellable, GError **error);
void otz_http_head_clear(OtzHttpHead *head);

void otz_http_body_init(OtzHttpBody *body, GDataInputStream *in,
                        const OtzHttpHead *head);
/* Bytes read, 0 at the end of the body, -1 on error. */
gssize otz_http_body_read(OtzHttpBody *body, void *buffer, gsize count,
                          GCancellable *cancellable, GError **error);

/* "bytes <start>-<end>/<total>"; FALSE for anything else (including "*"). */
gboolean otz_http_parse_content_range(const char *value, gint64 *start,
                                      gint64 *end, gint64 *total);

/* https only, allowed GitHub hosts only, and on github.com the path must be
 * under the allowed organization. Checked on every hop. */
gboolean otz_http_check_url(const char *url, GError **error);

typedef struct OtzHttpResponse OtzHttpResponse;

/* GET with up to 5 redirects. range_from >= 0 sends "Range: bytes=N-".
 * Returns with the final head read; the caller reads the body. */
OtzHttpResponse *otz_http_get(const char *url, gint64 range_from,
                              const char *accept, GCancellable *cancellable,
                              GError **error);
const OtzHttpHead *otz_http_response_head(OtzHttpResponse *response);
gssize otz_http_response_read(OtzHttpResponse *response, void *buffer,
                              gsize count, GCancellable *cancellable,
                              GError **error);
void otz_http_response_free(OtzHttpResponse *response);
G_DEFINE_AUTOPTR_CLEANUP_FUNC(OtzHttpResponse, otz_http_response_free)

/* Whole body of a 200 reply, refused beyond max_size. */
GBytes *otz_http_fetch(const char *url, const char *accept, gsize max_size,
                       GCancellable *cancellable, GError **error);
