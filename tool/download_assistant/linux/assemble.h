/* Placing verified cache files in the output folder, and joining split parts.
 * Nothing here hashes: every part was verified when it was downloaded, so the
 * checks are byte counts per append and the final size ("מהירות" in the doc). */
#pragma once

#include <gio/gio.h>

typedef void (*OtzBytesFunc)(gint64 delta, gpointer user_data);

/* Copies exactly length bytes from the current offset of in_fd to out_fd. */
gboolean otz_copy_bytes(int in_fd, int out_fd, gint64 length,
                        OtzBytesFunc progress, gpointer user_data,
                        GCancellable *cancellable, GError **error);

/* Hard-links src to dest (replacing dest); copies when a link is impossible,
 * e.g. another drive or FAT32/exFAT. */
gboolean otz_place_file(const char *src, const char *dest, gint64 size,
                        OtzBytesFunc progress, gpointer user_data,
                        GCancellable *cancellable, GError **error);

/* How many leading parts a partial assembly of `existing` bytes already holds;
 * *offset is where they end (the boundary to truncate to). */
guint otz_assembled_parts(const gint64 *sizes, guint count, gint64 existing,
                          gint64 *offset);

/* Appends parts[first..] to tmp_path after truncating it to the end of part
 * first-1, deletes each part and its .sha256 marker once appended, checks the
 * total and renames tmp_path to dest_path. */
gboolean otz_assemble(const char *tmp_path, const char *dest_path,
                      GPtrArray *part_paths, const gint64 *sizes, guint first,
                      gint64 total, OtzBytesFunc progress, gpointer user_data,
                      void (*on_part)(guint index, gpointer user_data),
                      GCancellable *cancellable, GError **error);
