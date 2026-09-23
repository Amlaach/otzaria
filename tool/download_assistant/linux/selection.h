/* Port of tool/release/download_assistant_selection.dart — the reference
 * implementation. tests/test_main.c compares this against
 * tool/download_assistant/fixtures/expected-selections.json. */
#pragma once

#include <glib.h>

#include "manifest.h"

#define OTZ_MAX_SINGLE_OUTPUT_FILE_SIZE G_GINT64_CONSTANT(4294967296)
#define OTZ_PORTABLE_PACKAGE_FORMAT "portable"

typedef struct {
  const char *platform;
  const char *architecture;   /* "" when the platform has no arch choice */
  const char *package_format; /* "" outside Linux */
} OtzTarget;

typedef struct {
  char *id;
  const char *caption;
  const char *description;
  GPtrArray *members; /* char* component ids, manifest order */
} OtzPreset;

void otz_preset_free(OtzPreset *preset);

/* Platforms in the order shown, and their display names. */
extern const char *const otz_assistant_platforms[];
const char *otz_platform_display_name(const char *platform);

gboolean otz_component_fits_target(const OtzComponent *component,
                                   const OtzTarget *target);

/* All the following return arrays of owned char*. */
GPtrArray *otz_platform_choices(const OtzManifest *manifest);
GPtrArray *otz_architecture_choices(const OtzManifest *manifest,
                                    const char *platform);
GPtrArray *otz_package_format_choices(const OtzManifest *manifest,
                                      const char *platform,
                                      const char *architecture);
/* os_release is the content of /etc/os-release, or NULL off Linux. */
char *otz_default_package_format(const char *os_release, GPtrArray *choices);

GPtrArray *otz_with_dependencies(const OtzManifest *manifest,
                                 GPtrArray *members, const OtzTarget *target);
/* OtzPreset*; empty presets and duplicates of an earlier one are dropped. */
GPtrArray *otz_build_presets(const OtzManifest *manifest,
                             const OtzTarget *target);

gboolean otz_should_assemble_split_asset(const OtzAsset *asset,
                                         const char *target_platform);
char *otz_output_subfolder_name(const char *target_platform);
GPtrArray *otz_planned_output_files(const OtzManifest *manifest,
                                    GPtrArray *selected_ids,
                                    const OtzTarget *target);
/* "" for a single file, otherwise the subfolder name. */
char *otz_planned_output_subfolder(GPtrArray *files,
                                   const char *target_platform);

gint64 otz_members_download_size(const OtzManifest *manifest,
                                 GPtrArray *members);
gboolean otz_string_array_contains(GPtrArray *array, const char *value);
