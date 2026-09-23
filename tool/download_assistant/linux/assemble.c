#include "assemble.h"

#include <errno.h>
#include <fcntl.h>
#include <glib/gstdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "otz_common.h"

#define COPY_BUFFER (1024 * 1024)

static gboolean io_error(GError **error, const char *what, const char *path) {
  int saved = errno;
  g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO, "%s %s: %s", what, path,
              g_strerror(saved));
  return FALSE;
}

gboolean otz_copy_bytes(int in_fd, int out_fd, gint64 length,
                        OtzBytesFunc progress, gpointer user_data,
                        GCancellable *cancellable, GError **error) {
  g_autofree guint8 *buffer = g_malloc(COPY_BUFFER);
  gint64 left = length;
  while (left > 0) {
    if (g_cancellable_set_error_if_cancelled(cancellable, error)) return FALSE;
    ssize_t n = read(in_fd, buffer, (size_t)MIN(left, (gint64)COPY_BUFFER));
    if (n < 0 && errno == EINTR) continue;
    if (n < 0) return io_error(error, "read", "");
    if (n == 0) {
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO,
                  "source ended %" G_GINT64_FORMAT " bytes early", left);
      return FALSE;
    }
    for (ssize_t written = 0; written < n;) {
      ssize_t w = write(out_fd, buffer + written, (size_t)(n - written));
      if (w < 0 && errno == EINTR) continue;
      if (w < 0) return io_error(error, "write", "");
      written += w;
    }
    left -= n;
    if (progress != NULL) progress(n, user_data);
  }
  return TRUE;
}

static gboolean same_file(const char *a, const char *b) {
  struct stat sa, sb;
  return stat(a, &sa) == 0 && stat(b, &sb) == 0 && sa.st_dev == sb.st_dev &&
         sa.st_ino == sb.st_ino;
}

gboolean otz_place_file(const char *src, const char *dest, gint64 size,
                        OtzBytesFunc progress, gpointer user_data,
                        GCancellable *cancellable, GError **error) {
  if (same_file(src, dest)) {
    if (progress != NULL) progress(size, user_data);
    return TRUE;
  }
  if (g_unlink(dest) != 0 && errno != ENOENT)
    return io_error(error, "cannot replace", dest);
  if (link(src, dest) == 0) {
    if (progress != NULL) progress(size, user_data);
    return TRUE;
  }

  g_autofree char *tmp = g_strconcat(dest, ".partial", NULL);
  int in_fd = open(src, O_RDONLY | O_CLOEXEC);
  if (in_fd < 0) return io_error(error, "open", src);
  int out_fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  if (out_fd < 0) {
    close(in_fd);
    return io_error(error, "create", tmp);
  }
  gboolean ok = otz_copy_bytes(in_fd, out_fd, size, progress, user_data,
                               cancellable, error);
  close(in_fd);
  if (close(out_fd) != 0 && ok) ok = io_error(error, "close", tmp);
  if (ok && g_rename(tmp, dest) != 0) ok = io_error(error, "rename", tmp);
  if (!ok) g_unlink(tmp);
  return ok;
}

guint otz_assembled_parts(const gint64 *sizes, guint count, gint64 existing,
                          gint64 *offset) {
  gint64 boundary = 0;
  guint done = 0;
  while (done < count && boundary + sizes[done] <= existing) {
    boundary += sizes[done];
    done++;
  }
  *offset = boundary;
  return done;
}

static gboolean verify_assembled(const char *path, const char *expected,
                                 OtzBytesFunc progress, gpointer user_data,
                                 GCancellable *cancellable, GError **error) {
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return io_error(error, "open", path);
  g_autoptr(GChecksum) checksum = g_checksum_new(G_CHECKSUM_SHA256);
  guint8 buffer[64 * 1024];
  for (;;) {
    if (g_cancellable_set_error_if_cancelled(cancellable, error)) {
      close(fd);
      return FALSE;
    }
    ssize_t n = read(fd, buffer, sizeof(buffer));
    if (n < 0 && errno == EINTR) continue;
    if (n < 0) {
      io_error(error, "read", path);
      close(fd);
      return FALSE;
    }
    if (n == 0) break;
    g_checksum_update(checksum, buffer, (gsize)n);
    if (progress != NULL) progress(n, user_data);
  }
  close(fd);
  if (strcmp(g_checksum_get_string(checksum), expected) == 0) return TRUE;
  g_unlink(path);
  g_set_error(error, OTZ_ERROR, OTZ_ERROR_CORRUPT, "%s: assembled sha256 mismatch", path);
  return FALSE;
}

gboolean otz_assemble(const char *tmp_path, const char *dest_path,
                      GPtrArray *part_paths, const gint64 *sizes, guint first,
                      gint64 total, const char *sha256,
                      OtzBytesFunc progress, gpointer user_data,
                      void (*on_part)(guint index, gpointer user_data),
                      void (*on_verify)(gpointer user_data),
                      GCancellable *cancellable, GError **error) {
  gint64 offset = 0;
  for (guint i = 0; i < first; i++) offset += sizes[i];

  int out_fd = open(tmp_path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
  if (out_fd < 0) return io_error(error, "create", tmp_path);
  if (ftruncate(out_fd, offset) != 0 || lseek(out_fd, offset, SEEK_SET) < 0) {
    io_error(error, "truncate", tmp_path);
    close(out_fd);
    return FALSE;
  }

  gboolean ok = TRUE;
  for (guint i = first; ok && i < part_paths->len; i++) {
    const char *part = g_ptr_array_index(part_paths, i);
    if (on_part != NULL) on_part(i, user_data);
    int in_fd = open(part, O_RDONLY | O_CLOEXEC);
    if (in_fd < 0) {
      ok = io_error(error, "open", part);
      break;
    }
    ok = otz_copy_bytes(in_fd, out_fd, sizes[i], progress, user_data,
                        cancellable, error);
    close(in_fd);
    if (!ok) break;
    offset += sizes[i];
    struct stat st;
    if (fstat(out_fd, &st) != 0 || st.st_size != offset) {
      g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO,
                  "part %s was not appended in full", part);
      ok = FALSE;
      break;
    }
    /* The part goes only after its append completed, so the tmp size always
     * lands on a part boundary for the next run to resume from. */
    g_autofree char *marker = g_strconcat(part, ".sha256", NULL);
    g_unlink(part);
    g_unlink(marker);
  }
  if (close(out_fd) != 0 && ok) ok = io_error(error, "close", tmp_path);
  if (!ok) return FALSE;

  if (offset != total) {
    g_set_error(error, OTZ_ERROR, OTZ_ERROR_IO,
                "assembled %" G_GINT64_FORMAT " bytes, expected %" G_GINT64_FORMAT,
                offset, total);
    return FALSE;
  }
  if (on_verify != NULL) on_verify(user_data);
  if (!verify_assembled(tmp_path, sha256, progress, user_data, cancellable,
                        error)) return FALSE;
  if (g_rename(tmp_path, dest_path) != 0)
    return io_error(error, "rename", tmp_path);
  return TRUE;
}
