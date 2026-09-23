#include "ui.h"

#include <glib/gi18n.h>
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>

#include "download.h"
#include "otz_common.h"
#include "paths.h"
#include "release.h"
#include "selection.h"

enum {
  PAGE_INTRO,
  PAGE_PLATFORM,
  PAGE_ARCH,
  PAGE_FORMAT,
  PAGE_PRESETS,
  PAGE_CUSTOM,
  PAGE_FOLDER,
  PAGE_PROGRESS,
  PAGE_FINISH,
  PAGE_COUNT,
};

#define PRESET_CUSTOM (-1)
#define PRESET_UNCHOSEN (-3)
#define SPEED_WINDOW_US (5 * G_USEC_PER_SEC)
#define MAX_SAMPLES 64

typedef struct {
  gint64 time;
  gint64 bytes;
} Sample;

typedef struct {
  const OtzUiOptions *options;
  GtkWidget *assistant;
  GtkWidget *pages[PAGE_COUNT];
  gboolean building; /* ignore toggles while radios are rebuilt */

  GtkWidget *intro_status, *intro_spinner, *intro_error_box, *intro_details;
  GtkWidget *platform_list, *arch_list, *format_list, *presets_list;
  GtkWidget *custom_list, *custom_hint;
  GtkWidget *folder_chooser, *folder_note, *folder_target, *folder_warning;
  GtkWidget *progress_phase, *progress_bar, *progress_detail;
  GtkWidget *finish_text, *finish_reveal, *finish_details, *finish_details_label;

  OtzManifest *manifest;
  char *pinned_tag;
  char *os_release;
  GPtrArray *platform_choices, *arch_choices, *format_choices;
  char *platform, *arch, *format;
  GPtrArray *presets;
  int preset_index;
  GHashTable *custom_checked;
  char *base_dir;
  gboolean base_fell_back;

  OtzJob *job;
  GCancellable *cancel;
  guint tick_id;
  gint64 started_us;
  Sample samples[MAX_SAMPLES];
  int sample_count;
  gboolean closing;
  gboolean succeeded;
  char *result_path;
  gboolean result_is_dir;
  int exit_code;
} Ui;

/* ------------------------------------------------------------- widgets */

static GtkWidget *new_page(void) {
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_container_set_border_width(GTK_CONTAINER(box), 18);
  return box;
}

static GtkWidget *add_label(GtkWidget *box, const char *text, gboolean bold) {
  GtkWidget *label = gtk_label_new(NULL);
  if (bold) {
    g_autofree char *markup = g_markup_printf_escaped("<b>%s</b>", text);
    gtk_label_set_markup(GTK_LABEL(label), markup);
  } else {
    gtk_label_set_text(GTK_LABEL(label), text);
  }
  gtk_label_set_line_wrap(GTK_LABEL(label), TRUE);
  gtk_label_set_xalign(GTK_LABEL(label), 0.0);
  gtk_widget_set_halign(label, GTK_ALIGN_FILL);
  gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 0);
  return label;
}

static GtkWidget *add_list(GtkWidget *box) {
  GtkWidget *list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_box_pack_start(GTK_BOX(box), list, FALSE, FALSE, 6);
  return list;
}

static void destroy_child(GtkWidget *child, gpointer data) {
  gtk_widget_destroy(child);
}

static void clear_container(GtkWidget *container) {
  gtk_container_foreach(GTK_CONTAINER(container), destroy_child, NULL);
}

/* One radio per option; `captions` and optional `notes` are plain text. */
static void fill_radios(Ui *ui, GtkWidget *list, GPtrArray *captions,
                        GPtrArray *notes, int active, GCallback on_toggled) {
  ui->building = TRUE;
  clear_container(list);
  GtkWidget *group = NULL;
  for (guint i = 0; i < captions->len; i++) {
    GtkWidget *radio = gtk_radio_button_new_from_widget(
        group != NULL ? GTK_RADIO_BUTTON(group) : NULL);
    group = radio;
    GtkWidget *label = gtk_label_new(NULL);
    const char *note = notes != NULL ? g_ptr_array_index(notes, i) : NULL;
    g_autofree char *markup =
        note != NULL
            ? g_markup_printf_escaped("<b>%s</b>\n<small>%s</small>",
                                      (const char *)g_ptr_array_index(captions, i),
                                      note)
            : g_markup_printf_escaped("%s", (const char *)g_ptr_array_index(captions, i));
    gtk_label_set_markup(GTK_LABEL(label), markup);
    gtk_label_set_line_wrap(GTK_LABEL(label), TRUE);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_container_add(GTK_CONTAINER(radio), label);
    g_object_set_data(G_OBJECT(radio), "index", GINT_TO_POINTER((int)i));
    g_signal_connect(radio, "toggled", on_toggled, ui);
    gtk_box_pack_start(GTK_BOX(list), radio, FALSE, FALSE, 0);
    if ((int)i == active)
      gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(radio), TRUE);
  }
  gtk_widget_show_all(list);
  ui->building = FALSE;
}

static int toggled_index(Ui *ui, GtkToggleButton *button) {
  if (ui->building || !gtk_toggle_button_get_active(button)) return -1;
  return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(button), "index"));
}

static int index_of(GPtrArray *array, const char *value) {
  for (guint i = 0; value != NULL && i < array->len; i++) {
    if (strcmp(g_ptr_array_index(array, i), value) == 0) return (int)i;
  }
  return -1;
}

/* GTK labels its assistant buttons from its own catalog, which is English
 * unless the Hebrew locale is installed; the whole interface must be Hebrew. */
static void relabel_buttons(GtkWidget *widget, gpointer data) {
  static const char *const map[][2] = {
      {"_Next", "הבא"},   {"_Back", "הקודם"}, {"_Cancel", "ביטול"},
      {"_Apply", "התחל בהורדה"}, {"_Close", "סגור"}, {"_Finish", "סיום"},
  };
  if (GTK_IS_BUTTON(widget)) {
    const char *label = gtk_button_get_label(GTK_BUTTON(widget));
    for (gsize i = 0; label != NULL && i < G_N_ELEMENTS(map); i++) {
      if (strcmp(label, map[i][0]) == 0 ||
          strcmp(label, g_dgettext("gtk30", map[i][0])) == 0) {
        gtk_button_set_use_underline(GTK_BUTTON(widget), FALSE);
        gtk_button_set_label(GTK_BUTTON(widget), map[i][1]);
        break;
      }
    }
  }
  if (GTK_IS_CONTAINER(widget))
    gtk_container_forall(GTK_CONTAINER(widget), relabel_buttons, data);
}

/* ------------------------------------------------------------- state */

static OtzTarget current_target(Ui *ui) {
  OtzTarget target = {ui->platform != NULL ? ui->platform : "",
                      ui->arch != NULL ? ui->arch : "",
                      ui->format != NULL ? ui->format : ""};
  return target;
}

static void set_arch(Ui *ui, const char *arch) {
  g_free(ui->arch);
  ui->arch = g_strdup(arch);
  g_clear_pointer(&ui->format_choices, g_ptr_array_unref);
  ui->format_choices =
      otz_package_format_choices(ui->manifest, ui->platform, ui->arch);
  g_free(ui->format);
  ui->format = otz_default_package_format(ui->os_release, ui->format_choices);
}

static void set_platform(Ui *ui, const char *platform) {
  g_free(ui->platform);
  ui->platform = g_strdup(platform);
  g_clear_pointer(&ui->arch_choices, g_ptr_array_unref);
  ui->arch_choices = otz_architecture_choices(ui->manifest, platform);
  const char *machine = otz_machine_architecture();
  const char *arch = index_of(ui->arch_choices, machine) >= 0 ? machine
                     : ui->arch_choices->len > 0 ? g_ptr_array_index(ui->arch_choices, 0)
                                                 : "";
  set_arch(ui, arch);
}

static GPtrArray *selected_ids(Ui *ui) {
  OtzTarget target = current_target(ui);
  if (ui->preset_index >= 0 && ui->presets != NULL &&
      ui->preset_index < (int)ui->presets->len) {
    const OtzPreset *preset = g_ptr_array_index(ui->presets, ui->preset_index);
    return otz_with_dependencies(ui->manifest, preset->members, &target);
  }
  g_autoptr(GPtrArray) checked = g_ptr_array_new();
  for (guint i = 0; i < ui->manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(ui->manifest->components, i);
    if (g_hash_table_contains(ui->custom_checked, component->id) &&
        otz_component_is_offered(ui->manifest, component, &target))
      g_ptr_array_add(checked, component->id);
  }
  return otz_with_dependencies(ui->manifest, checked, &target);
}

static gboolean page_skipped(Ui *ui, int page) {
  switch (page) {
    case PAGE_PLATFORM:
      return ui->platform_choices == NULL || ui->platform_choices->len <= 1;
    case PAGE_ARCH:
      return ui->arch_choices == NULL || ui->arch_choices->len <= 1;
    case PAGE_FORMAT:
      return ui->format_choices == NULL || ui->format_choices->len <= 1;
    case PAGE_CUSTOM:
      return ui->preset_index != PRESET_CUSTOM;
    default:
      return FALSE;
  }
}

static gint forward_page(gint current, gpointer data) {
  Ui *ui = data;
  for (int next = current + 1; next < PAGE_COUNT; next++) {
    if (!page_skipped(ui, next)) return next;
  }
  return -1;
}

static void set_complete(Ui *ui, int page, gboolean complete) {
  gtk_assistant_set_page_complete(GTK_ASSISTANT(ui->assistant), ui->pages[page],
                                  complete);
}

/* ------------------------------------------------------------- pages */

static void on_platform_toggled(GtkToggleButton *button, Ui *ui) {
  int index = toggled_index(ui, button);
  if (index < 0) return;
  set_platform(ui, g_ptr_array_index(ui->platform_choices, index));
  gtk_assistant_update_buttons_state(GTK_ASSISTANT(ui->assistant));
}

static void on_arch_toggled(GtkToggleButton *button, Ui *ui) {
  int index = toggled_index(ui, button);
  if (index < 0) return;
  set_arch(ui, g_ptr_array_index(ui->arch_choices, index));
  gtk_assistant_update_buttons_state(GTK_ASSISTANT(ui->assistant));
}

static void on_format_toggled(GtkToggleButton *button, Ui *ui) {
  int index = toggled_index(ui, button);
  if (index < 0) return;
  g_free(ui->format);
  ui->format = g_strdup(g_ptr_array_index(ui->format_choices, index));
}

static void on_preset_toggled(GtkToggleButton *button, Ui *ui) {
  int index = toggled_index(ui, button);
  if (index < 0) return;
  ui->preset_index = index < (int)ui->presets->len ? index : PRESET_CUSTOM;
  gtk_assistant_update_buttons_state(GTK_ASSISTANT(ui->assistant));
}

static void prepare_platform(Ui *ui) {
  g_autoptr(GPtrArray) captions = g_ptr_array_new();
  for (guint i = 0; i < ui->platform_choices->len; i++)
    g_ptr_array_add(captions, (gpointer)otz_platform_display_name(
                                  g_ptr_array_index(ui->platform_choices, i)));
  fill_radios(ui, ui->platform_list, captions, NULL,
              index_of(ui->platform_choices, ui->platform),
              G_CALLBACK(on_platform_toggled));
}

static const char *arch_caption(const char *arch) {
  if (strcmp(arch, "x64") == 0) return "מחשב רגיל";
  if (strcmp(arch, "arm64") == 0) return "מחשב עם מעבד מסוג ARM";
  return arch;
}

static const char *format_caption(const char *format) {
  if (strcmp(format, "deb") == 0) return "Ubuntu, Debian, Mint והפצות דומות (DEB)";
  if (strcmp(format, "rpm") == 0) return "Fedora, openSUSE והפצות דומות (RPM)";
  if (strcmp(format, OTZ_PORTABLE_PACKAGE_FORMAT) == 0)
    return "הפצה אחרת — ללא התקנה";
  return format;
}

static void prepare_arch(Ui *ui) {
  g_autoptr(GPtrArray) captions = g_ptr_array_new();
  for (guint i = 0; i < ui->arch_choices->len; i++)
    g_ptr_array_add(captions,
                    (gpointer)arch_caption(g_ptr_array_index(ui->arch_choices, i)));
  fill_radios(ui, ui->arch_list, captions, NULL, index_of(ui->arch_choices, ui->arch),
              G_CALLBACK(on_arch_toggled));
}

static void prepare_format(Ui *ui) {
  g_autoptr(GPtrArray) captions = g_ptr_array_new();
  for (guint i = 0; i < ui->format_choices->len; i++)
    g_ptr_array_add(captions, (gpointer)format_caption(
                                  g_ptr_array_index(ui->format_choices, i)));
  fill_radios(ui, ui->format_list, captions, NULL,
              index_of(ui->format_choices, ui->format),
              G_CALLBACK(on_format_toggled));
}

static void prepare_presets(Ui *ui) {
  OtzTarget target = current_target(ui);
  g_clear_pointer(&ui->presets, g_ptr_array_unref);
  ui->presets = otz_build_presets(ui->manifest, &target);
  if (ui->preset_index != PRESET_CUSTOM &&
      (ui->preset_index < 0 || ui->preset_index >= (int)ui->presets->len)) {
    ui->preset_index = ui->presets->len > 0 ? 0 : PRESET_CUSTOM;
    for (guint i = 0; i < ui->presets->len; i++) {
      const OtzPreset *preset = g_ptr_array_index(ui->presets, i);
      if (strcmp(preset->id, OTZ_DEFAULT_PRESET_ID) == 0)
        ui->preset_index = (int)i;
    }
  }

  g_autoptr(GPtrArray) captions = g_ptr_array_new_with_free_func(g_free);
  g_autoptr(GPtrArray) notes = g_ptr_array_new();
  for (guint i = 0; i < ui->presets->len; i++) {
    const OtzPreset *preset = g_ptr_array_index(ui->presets, i);
    g_autofree char *size =
        otz_human_size(otz_members_download_size(ui->manifest, preset->members));
    g_ptr_array_add(captions, g_strdup_printf("%s — %s", preset->caption, size));
    g_ptr_array_add(notes, (gpointer)preset->description);
  }
  g_ptr_array_add(captions, g_strdup("בחירה אישית"));
  g_ptr_array_add(notes, (gpointer) "אני רוצה לבחור בעצמי מה להוריד.");
  int active = ui->preset_index == PRESET_CUSTOM ? (int)ui->presets->len
                                                  : ui->preset_index;
  fill_radios(ui, ui->presets_list, captions, notes, active,
              G_CALLBACK(on_preset_toggled));
}

static void update_custom_complete(Ui *ui) {
  g_autoptr(GPtrArray) ids = selected_ids(ui);
  gboolean any = ids->len > 0;
  gtk_widget_set_visible(ui->custom_hint, !any);
  set_complete(ui, PAGE_CUSTOM, any);
}

static void on_custom_toggled(GtkToggleButton *button, Ui *ui) {
  const char *id = g_object_get_data(G_OBJECT(button), "component-id");
  if (gtk_toggle_button_get_active(button))
    g_hash_table_add(ui->custom_checked, g_strdup(id));
  else
    g_hash_table_remove(ui->custom_checked, id);
  update_custom_complete(ui);
}

static void prepare_custom(Ui *ui) {
  OtzTarget target = current_target(ui);
  clear_container(ui->custom_list);
  for (guint i = 0; i < ui->manifest->components->len; i++) {
    const OtzComponent *component = g_ptr_array_index(ui->manifest->components, i);
    if (!otz_component_is_offered(ui->manifest, component, &target)) continue;
    g_autofree char *size = otz_human_size(component->download_size);
    g_autofree char *caption =
        g_strdup_printf("%s — %s%s", component->name, size,
                        component->required ? " (נדרש)" : "");
    GtkWidget *check = gtk_check_button_new_with_label(caption);
    g_object_set_data_full(G_OBJECT(check), "component-id",
                           g_strdup(component->id), g_free);
    gtk_toggle_button_set_active(
        GTK_TOGGLE_BUTTON(check),
        g_hash_table_contains(ui->custom_checked, component->id));
    g_signal_connect(check, "toggled", G_CALLBACK(on_custom_toggled), ui);
    if (*component->description != '\0')
      gtk_widget_set_tooltip_text(check, component->description);
    gtk_box_pack_start(GTK_BOX(ui->custom_list), check, FALSE, FALSE, 0);
  }
  gtk_widget_show_all(ui->custom_list);
  update_custom_complete(ui);
}

static void update_folder(Ui *ui) {
  gboolean writable = ui->base_dir != NULL && otz_dir_is_writable(ui->base_dir);
  GString *warning = g_string_new(NULL);
  if (!writable) {
    g_string_append(warning, "לא ניתן לשמור בתיקייה שנבחרה. נסה תיקייה אחרת.");
  } else {
    OtzTarget target = current_target(ui);
    g_autoptr(GPtrArray) ids = selected_ids(ui);
    g_autofree char *cache = otz_cache_dir();
    g_autoptr(OtzJob) plan =
        otz_job_new(ui->manifest, ids, &target, cache, ui->base_dir, NULL);
    gint64 cache_bytes = 0, output_bytes = 0;
    gboolean same = FALSE;
    if (plan != NULL)
      otz_job_space_needs(plan, &cache_bytes, &output_bytes, &same);
    if (plan != NULL &&
        !otz_space_is_enough(cache_bytes, output_bytes, same, otz_free_space(cache),
                             otz_free_space(otz_job_output_dir(plan)))) {
      g_autofree char *size = otz_human_size(cache_bytes + output_bytes);
      g_string_append_printf(warning,
                             "נראה שאין מספיק מקום פנוי. דרושים בערך %s.", size);
    }
  }
  gtk_label_set_text(GTK_LABEL(ui->folder_warning), warning->str);
  gtk_widget_set_visible(ui->folder_warning, warning->len > 0);
  g_string_free(warning, TRUE);

  if (writable) {
    OtzTarget target = current_target(ui);
    g_autoptr(GPtrArray) ids = selected_ids(ui);
    g_autoptr(GPtrArray) files =
        otz_planned_output_files(ui->manifest, ids, &target);
    g_autofree char *sub = otz_planned_output_subfolder(files, target.platform);
    g_autofree char *dir = *sub != '\0' ? g_build_filename(ui->base_dir, sub, NULL)
                                        : g_strdup(ui->base_dir);
    g_autofree char *shown = otz_ltr_isolate(dir);
    g_autofree char *text = g_strdup_printf("התוצאה תישמר בתיקייה:\n%s", shown);
    gtk_label_set_text(GTK_LABEL(ui->folder_target), text);
  } else {
    gtk_label_set_text(GTK_LABEL(ui->folder_target), "");
  }
  set_complete(ui, PAGE_FOLDER, writable);
}

static void on_folder_changed(GtkFileChooser *chooser, Ui *ui) {
  g_autofree char *folder = gtk_file_chooser_get_filename(chooser);
  if (folder == NULL || g_strcmp0(folder, ui->base_dir) == 0) return;
  g_free(ui->base_dir);
  ui->base_dir = g_steal_pointer(&folder);
  update_folder(ui);
}

static void prepare_folder(Ui *ui) {
  if (ui->base_dir == NULL)
    ui->base_dir = otz_default_output_dir(&ui->base_fell_back);
  if (ui->options->dev_output != NULL) {
    g_free(ui->base_dir);
    ui->base_dir = g_strdup(ui->options->dev_output);
    g_mkdir_with_parents(ui->base_dir, 0755);
  }
  gtk_widget_set_visible(ui->folder_note, ui->base_fell_back);
  g_mkdir_with_parents(ui->base_dir, 0755);
  gtk_file_chooser_set_filename(GTK_FILE_CHOOSER(ui->folder_chooser), ui->base_dir);
  update_folder(ui);
}

/* ------------------------------------------------------------- progress */

static char *speed_text(double bytes_per_second) {
  if (bytes_per_second >= 1048576)
    return g_strdup_printf("%.1f מגה לשנייה", bytes_per_second / 1048576);
  return g_strdup_printf("%d קילו לשנייה", (int)(bytes_per_second / 1024));
}

static char *eta_text(double seconds) {
  if (seconds < 60) return g_strdup("פחות מדקה");
  int minutes = (int)(seconds / 60 + 0.5);
  if (minutes < 2) return g_strdup("בערך דקה");
  if (minutes < 60) return g_strdup_printf("בערך %d דקות", minutes);
  int hours = minutes / 60;
  minutes %= 60;
  const char *hour_text = hours == 1 ? "שעה" : NULL;
  g_autofree char *hours_part =
      hour_text != NULL ? g_strdup(hour_text) : g_strdup_printf("%d שעות", hours);
  if (minutes == 0) return g_strdup_printf("בערך %s", hours_part);
  return g_strdup_printf("בערך %s ו-%d דקות", hours_part, minutes);
}

/* Moving average over the last ~5 seconds of samples. */
static double current_speed(Ui *ui, gint64 now, gint64 bytes) {
  if (ui->sample_count == MAX_SAMPLES) {
    memmove(ui->samples, ui->samples + 1, sizeof(Sample) * (MAX_SAMPLES - 1));
    ui->sample_count--;
  }
  ui->samples[ui->sample_count++] = (Sample){now, bytes};
  int oldest = 0;
  while (oldest < ui->sample_count - 1 &&
         now - ui->samples[oldest].time > SPEED_WINDOW_US)
    oldest++;
  gint64 span = now - ui->samples[oldest].time;
  if (span < G_USEC_PER_SEC) return -1;
  return (double)(bytes - ui->samples[oldest].bytes) * G_USEC_PER_SEC / span;
}

static gboolean on_tick(gpointer data) {
  Ui *ui = data;
  if (ui->job == NULL) return G_SOURCE_REMOVE;
  OtzProgress p;
  otz_job_get_progress(ui->job, &p);
  g_autofree char *phase = NULL;
  g_autofree char *detail = NULL;
  double fraction = -1;
  const char *name = p.detail != NULL ? p.detail : "";

  if (p.phase == OTZ_PHASE_DOWNLOAD) {
    phase = g_strdup_printf("מוריד את הקבצים — הושלמו %u מתוך %u", p.files_done,
                            p.files_total);
    g_autofree char *done = otz_human_size(p.download_done);
    g_autofree char *total = otz_human_size(p.download_total);
    GString *text = g_string_new(NULL);
    g_string_append_printf(text, "סך הכול: %s מתוך %s", done, total);
    double speed = current_speed(ui, g_get_monotonic_time(), p.download_done);
    if (speed > 0) {
      g_autofree char *rate = speed_text(speed);
      g_autofree char *eta = eta_text((p.download_total - p.download_done) / speed);
      g_string_append_printf(text, " · מהירות: %s · נותרו %s", rate, eta);
    }
    detail = g_string_free(text, FALSE);
    if (p.download_total > 0)
      fraction = (double)p.download_done / (double)p.download_total;
  } else if (p.phase != OTZ_PHASE_DONE && p.phase_total > 0) {
    g_autofree char *done = otz_human_size(p.phase_done);
    g_autofree char *total = otz_human_size(p.phase_total);
    if (p.phase == OTZ_PHASE_CHECK) {
      phase = g_strdup("בודק קבצים שכבר הורדו");
      detail = g_strdup_printf("%s · %s מתוך %s", name, done, total);
    } else if (p.phase == OTZ_PHASE_ASSEMBLE) {
      phase = g_strdup_printf("מחבר את הקבצים: %s", name);
      detail = g_strdup_printf("חלק %u מתוך %u · %s מתוך %s", p.part_index + 1,
                               p.part_count, done, total);
    } else if (p.phase == OTZ_PHASE_VERIFY_ASSEMBLY) {
      phase = g_strdup_printf("בודק את הקובץ המאוחד: %s", name);
      detail = g_strdup_printf("%s מתוך %s", done, total);
    } else {
      phase = g_strdup_printf("מעתיק לתיקייה שנבחרה: %s", name);
      detail = g_strdup_printf("%s מתוך %s", done, total);
    }
    fraction = (double)p.phase_done / (double)p.phase_total;
  } else {
    phase = g_strdup("מכין את ההורדה…");
    detail = g_strdup("");
  }
  gtk_label_set_text(GTK_LABEL(ui->progress_phase), phase);
  gtk_label_set_text(GTK_LABEL(ui->progress_detail), detail);
  if (fraction >= 0)
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(ui->progress_bar),
                                  CLAMP(fraction, 0.0, 1.0));
  else
    gtk_progress_bar_pulse(GTK_PROGRESS_BAR(ui->progress_bar));
  otz_progress_clear(&p);
  return G_SOURCE_CONTINUE;
}

static const char *failure_text(OtzFailure failure) {
  switch (failure) {
    case OTZ_FAILURE_CORRUPT: return "אחד הקבצים שהורדו נמצא פגום ולא נשמר.";
    case OTZ_FAILURE_CACHE:
      return "לא ניתן היה לשמור את הקבצים שירדו. ייתכן שאין מספיק מקום פנוי.";
    case OTZ_FAILURE_ASSEMBLE:
      return "לא ניתן היה לכתוב את הקובץ המאוחד. ייתכן שאין מספיק מקום פנוי.";
    case OTZ_FAILURE_PLACE: return "לא ניתן היה להעתיק את הקבצים לתיקייה שנבחרה.";
    case OTZ_FAILURE_CANCELLED: return "ההורדה הופסקה.";
    default: return "לא ניתן להכין את ההתקנה משום שאחד הקבצים הדרושים אינו זמין.";
  }
}

static void show_failure(Ui *ui, const char *text, const char *technical) {
  gtk_assistant_set_page_title(GTK_ASSISTANT(ui->assistant), ui->pages[PAGE_FINISH],
                               "לא ניתן להשלים את ההכנה");
  g_autofree char *full = g_strconcat(
      text, "\n\nמה שכבר ירד נשמר, והפעלה חוזרת של המסייע תמשיך מאותו מקום.", NULL);
  gtk_label_set_text(GTK_LABEL(ui->finish_text), full);
  gtk_label_set_text(GTK_LABEL(ui->finish_details_label), technical);
  gtk_widget_show(ui->finish_details);
  gtk_widget_hide(ui->finish_reveal);
  g_printerr("otzaria-download-assistant: %s\n", technical);
}

static void show_success(Ui *ui) {
  GPtrArray *files = otz_job_output_files(ui->job);
  const char *dir = otz_job_output_dir(ui->job);
  g_autofree char *shown_dir = otz_ltr_isolate(dir);
  GString *text = g_string_new(NULL);
  if (files->len == 1) {
    const char *name = g_ptr_array_index(files, 0);
    g_autofree char *shown_name = otz_ltr_isolate(name);
    g_string_append_printf(text,
                           "הקובץ מוכן:\n%s\n\nהוא נמצא בתיקייה:\n%s\n\n"
                           "העתק את הקובץ הזה לדיסק-און-קי ומשם למחשב המנותק.",
                           shown_name, shown_dir);
    g_free(ui->result_path);
    ui->result_path = g_build_filename(dir, name, NULL);
    ui->result_is_dir = FALSE;
    gtk_button_set_label(GTK_BUTTON(ui->finish_reveal), "הצג את הקובץ שהוכן");
  } else {
    const char *installer = NULL;
    for (guint i = 0; installer == NULL && i < files->len; i++) {
      g_autofree char *lower = g_ascii_strdown(g_ptr_array_index(files, i), -1);
      if (g_str_has_suffix(lower, ".exe")) installer = g_ptr_array_index(files, i);
    }
    g_autofree char *shown_installer =
        installer != NULL ? otz_ltr_isolate(installer) : g_strdup("קובץ ההתקנה");
    g_string_append_printf(
        text,
        "ההתקנה מוכנה בתיקייה:\n%s\n\nהעתק את כל התיקייה הזאת לדיסק-און-קי, "
        "ובמחשב המנותק הפעל מתוכה את %s. הקבצים חייבים להישאר יחד "
        "באותה תיקייה. אין צורך בחיבור לאינטרנט ואין צורך בתוכנות נוספות.\n\n"
        "הקבצים שהוכנו:",
        shown_dir, shown_installer);
    for (guint i = 0; i < files->len; i++) {
      g_autofree char *shown = otz_ltr_isolate(g_ptr_array_index(files, i));
      g_string_append_printf(text, "\n• %s", shown);
    }
    g_free(ui->result_path);
    ui->result_path = g_strdup(dir);
    ui->result_is_dir = TRUE;
    gtk_button_set_label(GTK_BUTTON(ui->finish_reveal), "הצג את התיקייה שהוכנה");
  }
  GPtrArray *unjoined = otz_job_unjoined_assets(ui->job);
  for (guint i = 0; i < unjoined->len; i++) {
    const char *name = g_ptr_array_index(unjoined, i);
    g_autofree char *command = g_strdup_printf("cat %s.part-* > %s", name, name);
    g_autofree char *shown = otz_ltr_isolate(command);
    g_string_append_printf(text,
                           "\n\nהקובץ %s גדול מדי לקובץ אחד ולכן נשאר בחלקים. "
                           "במחשב היעד מחברים אותם בפקודה:\n%s",
                           name, shown);
  }
  gtk_label_set_text(GTK_LABEL(ui->finish_text), text->str);
  g_string_free(text, TRUE);
  gtk_widget_hide(ui->finish_details);
  gtk_widget_show(ui->finish_reveal);
  gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(ui->finish_reveal),
                               ui->options->dev_auto_preset == NULL);
}

static void auto_report(Ui *ui, const char *technical) {
  if (ui->options->dev_auto_preset == NULL) return;
  double seconds = (g_get_monotonic_time() - ui->started_us) / 1e6;
  if (ui->succeeded) {
    gint64 downloaded = otz_job_downloaded_bytes(ui->job);
    printf("result: ok\ndir: %s\nfiles: %u\ndownloaded: %" G_GINT64_FORMAT
           "\nhashed: %" G_GINT64_FORMAT "\nseconds: %.1f\nMB/s: %.2f\n",
           otz_job_output_dir(ui->job), otz_job_output_files(ui->job)->len,
           downloaded, otz_job_hashed_bytes(ui->job), seconds,
           seconds > 0 ? downloaded / seconds / 1e6 : 0.0);
  } else {
    printf("result: failed\nerror: %s\n", technical);
  }
  fflush(stdout);
  ui->exit_code = ui->succeeded ? 0 : 1;
  gtk_widget_destroy(ui->assistant);
}

static void on_job_done(GObject *source, GAsyncResult *result, gpointer data) {
  Ui *ui = data;
  g_autoptr(GError) error = NULL;
  ui->succeeded = otz_job_run_finish(ui->job, result, &error);
  if (ui->tick_id != 0) {
    on_tick(ui);
    g_source_remove(ui->tick_id);
    ui->tick_id = 0;
  }
  if (ui->closing) {
    gtk_widget_destroy(ui->assistant);
    return;
  }
  if (ui->succeeded) {
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(ui->progress_bar), 1.0);
    show_success(ui);
  } else {
    show_failure(ui, failure_text(otz_job_failure(ui->job)), error->message);
  }
  set_complete(ui, PAGE_PROGRESS, TRUE);
  gtk_assistant_next_page(GTK_ASSISTANT(ui->assistant));
  auto_report(ui, error != NULL ? error->message : NULL);
}

static void start_job(Ui *ui) {
  OtzTarget target = current_target(ui);
  g_autoptr(GPtrArray) ids = selected_ids(ui);
  g_autofree char *cache = otz_cache_dir();
  g_autoptr(GError) error = NULL;
  gtk_assistant_commit(GTK_ASSISTANT(ui->assistant));
  ui->started_us = g_get_monotonic_time();
  ui->job = otz_job_new(ui->manifest, ids, &target, cache, ui->base_dir, &error);
  if (ui->job == NULL) {
    show_failure(ui, failure_text(OTZ_FAILURE_UNAVAILABLE), error->message);
    set_complete(ui, PAGE_PROGRESS, TRUE);
    gtk_assistant_next_page(GTK_ASSISTANT(ui->assistant));
    auto_report(ui, error->message);
    return;
  }
  ui->cancel = g_cancellable_new();
  ui->sample_count = 0;
  ui->tick_id = g_timeout_add(250, on_tick, ui);
  otz_job_run_async(ui->job, ui->cancel, on_job_done, ui);
}

/* ------------------------------------------------------------- intro */

static void on_open_downloads(GtkButton *button, Ui *ui) {
  g_autofree char *url =
      g_strdup_printf("https://github.com/%s/otzaria/releases", otz_allowed_owner());
  g_app_info_launch_default_for_uri(url, NULL, NULL);
}

typedef struct {
  OtzManifest *manifest;
  char *tag;
  const char *user_message;
  GError *error;
} LoadResult;

static void free_load_result(gpointer data) {
  LoadResult *result = data;
  otz_manifest_free(result->manifest);
  g_free(result->tag);
  g_clear_error(&result->error);
  g_free(result);
}

/* Runs off the main thread and sees only its own copy of the input: the Ui
 * lives on otz_ui_run's stack, which may be gone by the time this finishes. */
static void load_in_thread(GTask *task, gpointer source, gpointer task_data,
                           GCancellable *cancellable) {
  const char *dev_manifest = task_data;
  LoadResult *result = g_new0(LoadResult, 1);
  if (dev_manifest != NULL) {
    result->user_message = "לא ניתן לקרוא את רשימת הקבצים של אוצריא.";
    result->manifest = otz_load_manifest_file(dev_manifest, &result->error);
    if (result->manifest != NULL)
      result->tag = g_strdup(result->manifest->release_tag);
  } else {
    result->manifest = otz_load_release_manifest(
        &result->tag, &result->user_message, cancellable, &result->error);
  }
  g_task_return_pointer(task, result, free_load_result);
}

static void on_manifest_loaded(GObject *source, GAsyncResult *async, gpointer data) {
  Ui *ui = data;
  GTask *task = G_TASK(async);
  g_autoptr(GError) error = NULL;
  LoadResult *result = g_task_propagate_pointer(task, &error);
  gtk_spinner_stop(GTK_SPINNER(ui->intro_spinner));
  gtk_widget_hide(ui->intro_spinner);
  const char *message = "לא ניתן לקרוא את רשימת הקבצים של אוצריא.";
  if (result != NULL && result->manifest == NULL) {
    if (result->user_message != NULL) message = result->user_message;
    error = g_steal_pointer(&result->error);
    free_load_result(g_steal_pointer(&result));
    if (error == NULL)
      error = g_error_new_literal(OTZ_ERROR, OTZ_ERROR_PARSE, "no manifest");
  }
  if (result == NULL) {
    if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) return;
    gtk_label_set_text(GTK_LABEL(ui->intro_status), message);
    gtk_label_set_text(GTK_LABEL(ui->intro_details), error->message);
    gtk_widget_show_all(ui->intro_error_box);
    g_printerr("otzaria-download-assistant: %s\n", error->message);
    if (ui->options->dev_auto_preset != NULL) {
      printf("result: failed\nerror: %s\n", error->message);
      ui->exit_code = 1;
      gtk_widget_destroy(ui->assistant);
    }
    return;
  }
  ui->manifest = g_steal_pointer(&result->manifest);
  ui->pinned_tag = g_steal_pointer(&result->tag);
  free_load_result(result);
  g_debug("manifest %s: %u components", ui->pinned_tag,
          ui->manifest->components->len);

  ui->platform_choices = otz_platform_choices(ui->manifest);
  if (ui->platform_choices->len == 0) {
    gtk_label_set_text(GTK_LABEL(ui->intro_status),
                       "לא ניתן לקרוא את רשימת הקבצים של אוצריא.");
    return;
  }
  const char *wanted =
      ui->options->dev_platform != NULL ? ui->options->dev_platform : "linux";
  int index = index_of(ui->platform_choices, wanted);
  set_platform(ui, g_ptr_array_index(ui->platform_choices, index >= 0 ? index : 0));

  gtk_label_set_text(GTK_LABEL(ui->intro_status), "אפשר להמשיך.");
  set_complete(ui, PAGE_INTRO, TRUE);
  if (ui->options->dev_auto_preset != NULL)
    gtk_assistant_next_page(GTK_ASSISTANT(ui->assistant));
}

/* ------------------------------------------------------------- signals */

static gboolean auto_step(gpointer data) {
  Ui *ui = data;
  GtkAssistant *assistant = GTK_ASSISTANT(ui->assistant);
  int page = gtk_assistant_get_current_page(assistant);
  if (page == PAGE_PRESETS) {
    ui->preset_index = -2;
    for (guint i = 0; i < ui->presets->len; i++) {
      const OtzPreset *preset = g_ptr_array_index(ui->presets, i);
      if (strcmp(preset->id, ui->options->dev_auto_preset) == 0)
        ui->preset_index = (int)i;
    }
    if (ui->preset_index == -2) {
      printf("result: failed\nerror: no preset '%s' for this target\n",
             ui->options->dev_auto_preset);
      ui->exit_code = 1;
      gtk_widget_destroy(ui->assistant);
      return G_SOURCE_REMOVE;
    }
  }
  if (page < PAGE_PROGRESS &&
      gtk_assistant_get_page_complete(assistant, ui->pages[page]))
    gtk_assistant_next_page(assistant);
  return G_SOURCE_REMOVE;
}

static void on_prepare(GtkAssistant *assistant, GtkWidget *page, Ui *ui) {
  int index = gtk_assistant_get_current_page(assistant);
  switch (index) {
    case PAGE_PLATFORM: prepare_platform(ui); break;
    case PAGE_ARCH: prepare_arch(ui); break;
    case PAGE_FORMAT: prepare_format(ui); break;
    case PAGE_PRESETS: prepare_presets(ui); break;
    case PAGE_CUSTOM: prepare_custom(ui); break;
    case PAGE_FOLDER: prepare_folder(ui); break;
    case PAGE_PROGRESS: start_job(ui); break;
    default: break;
  }
  relabel_buttons(ui->assistant, NULL);
  if (ui->options->dev_auto_preset != NULL && index > PAGE_INTRO &&
      index < PAGE_PROGRESS)
    g_idle_add(auto_step, ui);
}

static void on_cancel(GtkAssistant *assistant, Ui *ui) {
  if (ui->job != NULL && ui->tick_id != 0) {
    /* The window closes once the download threads have stopped writing. */
    ui->closing = TRUE;
    g_cancellable_cancel(ui->cancel);
    gtk_widget_set_sensitive(ui->assistant, FALSE);
    return;
  }
  gtk_widget_destroy(ui->assistant);
}

static void on_close(GtkAssistant *assistant, Ui *ui) {
  if (ui->succeeded && ui->result_path != NULL &&
      gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(ui->finish_reveal)))
    otz_reveal(ui->result_path, ui->result_is_dir);
  gtk_widget_destroy(ui->assistant);
}

static gboolean on_delete(GtkWidget *widget, GdkEvent *event, Ui *ui) {
  on_cancel(GTK_ASSISTANT(widget), ui);
  return TRUE;
}

/* ------------------------------------------------------------- build */

static void append_page(Ui *ui, int index, GtkWidget *page, const char *title,
                        GtkAssistantPageType type, gboolean complete) {
  ui->pages[index] = page;
  gtk_assistant_append_page(GTK_ASSISTANT(ui->assistant), page);
  gtk_assistant_set_page_title(GTK_ASSISTANT(ui->assistant), page, title);
  gtk_assistant_set_page_type(GTK_ASSISTANT(ui->assistant), page, type);
  gtk_assistant_set_page_complete(GTK_ASSISTANT(ui->assistant), page, complete);
}

static void build(Ui *ui) {
  ui->assistant = gtk_assistant_new();
  gtk_window_set_title(GTK_WINDOW(ui->assistant), "מסייע הורדה לאוצריא");
  gtk_window_set_default_size(GTK_WINDOW(ui->assistant), 720, 520);

  GtkWidget *page = new_page();
  add_label(page, "כלי זה אינו מתקין את אוצריא.", TRUE);
  add_label(page,
            "הכלי מוריד את הקבצים הדרושים ומכין תיקייה להתקנה במחשב אחר — גם "
            "במחשב ללא אינטרנט, ובכל מערכת הפעלה.",
            FALSE);
  add_label(page,
            "יש אינטרנט במחשב שבו תותקן אוצריא? מספיקה ההתקנה הבסיסית — "
            "הספרייה תרד מתוך התוכנה.",
            FALSE);
  GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  ui->intro_spinner = gtk_spinner_new();
  gtk_spinner_start(GTK_SPINNER(ui->intro_spinner));
  gtk_box_pack_start(GTK_BOX(row), ui->intro_spinner, FALSE, FALSE, 0);
  ui->intro_status = gtk_label_new("טוען את רשימת הקבצים של אוצריא…");
  gtk_label_set_line_wrap(GTK_LABEL(ui->intro_status), TRUE);
  gtk_label_set_xalign(GTK_LABEL(ui->intro_status), 0.0);
  gtk_box_pack_start(GTK_BOX(row), ui->intro_status, TRUE, TRUE, 0);
  gtk_box_pack_start(GTK_BOX(page), row, FALSE, FALSE, 12);
  ui->intro_error_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  add_label(ui->intro_error_box,
            "אפשר לפתוח את עמוד ההורדות של אוצריא בדפדפן ולהוריד משם ידנית "
            "(אפשרות מוגבלת: המסייע לא יוכל לבדוק את הקבצים או לחבר אותם).",
            FALSE);
  GtkWidget *open = gtk_button_new_with_label("פתח את עמוד ההורדות בדפדפן");
  gtk_widget_set_halign(open, GTK_ALIGN_START);
  g_signal_connect(open, "clicked", G_CALLBACK(on_open_downloads), ui);
  gtk_box_pack_start(GTK_BOX(ui->intro_error_box), open, FALSE, FALSE, 0);
  GtkWidget *expander = gtk_expander_new("פרטים טכניים");
  ui->intro_details = gtk_label_new(NULL);
  gtk_label_set_selectable(GTK_LABEL(ui->intro_details), TRUE);
  gtk_label_set_line_wrap(GTK_LABEL(ui->intro_details), TRUE);
  gtk_container_add(GTK_CONTAINER(expander), ui->intro_details);
  gtk_box_pack_start(GTK_BOX(ui->intro_error_box), expander, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(page), ui->intro_error_box, FALSE, FALSE, 0);
  gtk_widget_set_no_show_all(ui->intro_error_box, TRUE);
  append_page(ui, PAGE_INTRO, page, "אוצריא — מסייע הורדה", GTK_ASSISTANT_PAGE_INTRO,
              FALSE);

  page = new_page();
  add_label(page, "לאיזו מערכת הפעלה מכינים את ההתקנה?", TRUE);
  add_label(page, "ברירת המחדל היא מערכת ההפעלה של המחשב הזה.", FALSE);
  ui->platform_list = add_list(page);
  append_page(ui, PAGE_PLATFORM, page, "המחשב שאליו מכינים",
              GTK_ASSISTANT_PAGE_CONTENT, TRUE);

  page = new_page();
  add_label(page, "איזה סוג מחשב הוא היעד?", TRUE);
  add_label(page,
            "אם אינך יודע, השאר את הבחירה המסומנת — היא מתאימה למחשב הזה.", FALSE);
  ui->arch_list = add_list(page);
  append_page(ui, PAGE_ARCH, page, "המחשב שאליו מכינים", GTK_ASSISTANT_PAGE_CONTENT,
              TRUE);

  page = new_page();
  add_label(page, "איזו הפצת Linux מותקנת במחשב היעד?", TRUE);
  add_label(page, "אם אינך יודע, השאר את הבחירה המסומנת.", FALSE);
  ui->format_list = add_list(page);
  append_page(ui, PAGE_FORMAT, page, "המחשב שאליו מכינים",
              GTK_ASSISTANT_PAGE_CONTENT, TRUE);

  page = new_page();
  add_label(page, "בחר את היקף ההורדה.", TRUE);
  add_label(page, "אפשר לשנות את הבחירה בהמשך.", FALSE);
  ui->presets_list = add_list(page);
  append_page(ui, PAGE_PRESETS, page, "מה להוריד", GTK_ASSISTANT_PAGE_CONTENT, TRUE);

  page = new_page();
  add_label(page, "סמן את הרכיבים שברצונך להוריד.", TRUE);
  add_label(page, "ליד כל רכיב מופיע גודל ההורדה שלו.", FALSE);
  GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER,
                                 GTK_POLICY_AUTOMATIC);
  ui->custom_list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  gtk_container_add(GTK_CONTAINER(scroll), ui->custom_list);
  gtk_box_pack_start(GTK_BOX(page), scroll, TRUE, TRUE, 0);
  ui->custom_hint = add_label(page, "יש לבחור לפחות רכיב אחד להורדה.", FALSE);
  gtk_widget_set_no_show_all(ui->custom_hint, TRUE);
  append_page(ui, PAGE_CUSTOM, page, "בחירה אישית", GTK_ASSISTANT_PAGE_CONTENT,
              FALSE);

  page = new_page();
  add_label(page, "כברירת מחדל התוצאה נשמרת ליד המסייע עצמו.", TRUE);
  add_label(page,
            "אפשר לבחור תיקייה אחרת. בסיום אפשר יהיה להעתיק את התוצאה "
            "לדיסק-און-קי ולהעביר אותה למחשב המנותק.",
            FALSE);
  ui->folder_note = add_label(page,
                              "אי אפשר לשמור בתיקייה שממנה הופעל המסייע (למשל "
                              "דיסק-און-קי לקריאה בלבד), ולכן הוצעה כאן תיקייה אחרת.",
                              FALSE);
  gtk_widget_set_no_show_all(ui->folder_note, TRUE);
  ui->folder_chooser = gtk_file_chooser_button_new("בחירת תיקייה",
                                                   GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER);
  g_signal_connect(ui->folder_chooser, "file-set",
                   G_CALLBACK(on_folder_changed), ui);
  gtk_box_pack_start(GTK_BOX(page), ui->folder_chooser, FALSE, FALSE, 0);
  ui->folder_target = add_label(page, "", FALSE);
  ui->folder_warning = add_label(page, "", TRUE);
  gtk_widget_set_no_show_all(ui->folder_warning, TRUE);
  append_page(ui, PAGE_FOLDER, page, "לאן לשמור", GTK_ASSISTANT_PAGE_CONFIRM, FALSE);

  page = new_page();
  add_label(page,
            "הקבצים יורדים מאתר אוצריא. אפשר לעצור בכל רגע — מה שכבר ירד יישמר.",
            FALSE);
  ui->progress_phase = add_label(page, "", TRUE);
  ui->progress_bar = gtk_progress_bar_new();
  gtk_box_pack_start(GTK_BOX(page), ui->progress_bar, FALSE, FALSE, 0);
  ui->progress_detail = add_label(page, "", FALSE);
  append_page(ui, PAGE_PROGRESS, page, "הורדת הקבצים", GTK_ASSISTANT_PAGE_PROGRESS,
              FALSE);

  page = new_page();
  ui->finish_text = add_label(page, "", FALSE);
  gtk_label_set_selectable(GTK_LABEL(ui->finish_text), TRUE);
  ui->finish_reveal = gtk_check_button_new_with_label("הצג את התיקייה שהוכנה");
  gtk_box_pack_start(GTK_BOX(page), ui->finish_reveal, FALSE, FALSE, 0);
  ui->finish_details = gtk_expander_new("פרטים טכניים");
  ui->finish_details_label = gtk_label_new(NULL);
  gtk_label_set_selectable(GTK_LABEL(ui->finish_details_label), TRUE);
  gtk_label_set_line_wrap(GTK_LABEL(ui->finish_details_label), TRUE);
  gtk_container_add(GTK_CONTAINER(ui->finish_details), ui->finish_details_label);
  gtk_box_pack_start(GTK_BOX(page), ui->finish_details, FALSE, FALSE, 0);
  gtk_widget_set_no_show_all(ui->finish_details, TRUE);
  append_page(ui, PAGE_FINISH, page, "ההתקנה מוכנה", GTK_ASSISTANT_PAGE_SUMMARY, TRUE);

  gtk_assistant_set_forward_page_func(GTK_ASSISTANT(ui->assistant), forward_page, ui,
                                      NULL);
  g_signal_connect(ui->assistant, "prepare", G_CALLBACK(on_prepare), ui);
  g_signal_connect(ui->assistant, "cancel", G_CALLBACK(on_cancel), ui);
  g_signal_connect(ui->assistant, "close", G_CALLBACK(on_close), ui);
  g_signal_connect(ui->assistant, "delete-event", G_CALLBACK(on_delete), ui);
  g_signal_connect(ui->assistant, "destroy", G_CALLBACK(gtk_main_quit), NULL);
}

static gboolean quit_self_test(gpointer data) {
  gtk_widget_destroy(GTK_WIDGET(data));
  return G_SOURCE_REMOVE;
}

int otz_ui_run(const OtzUiOptions *options) {
  Ui ui = {0};
  ui.options = options;
  ui.preset_index = PRESET_UNCHOSEN;
  ui.os_release = otz_read_os_release();
  ui.custom_checked = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);

  gtk_widget_set_default_direction(GTK_TEXT_DIR_RTL);
  build(&ui);
  gtk_widget_show_all(ui.assistant);
  relabel_buttons(ui.assistant, NULL);

  g_autoptr(GCancellable) load_cancel = g_cancellable_new();
  if (options->self_test) {
    g_timeout_add(500, quit_self_test, ui.assistant);
  } else {
    g_autoptr(GTask) task = g_task_new(NULL, load_cancel, on_manifest_loaded, &ui);
    g_task_set_task_data(task, g_strdup(options->dev_manifest), g_free);
    g_task_run_in_thread(task, load_in_thread);
  }
  gtk_main();
  g_cancellable_cancel(load_cancel);

  int code = ui.exit_code;
  if (ui.job != NULL) otz_job_free(ui.job);
  g_clear_object(&ui.cancel);
  otz_manifest_free(ui.manifest);
  g_free(ui.pinned_tag);
  g_free(ui.os_release);
  g_clear_pointer(&ui.platform_choices, g_ptr_array_unref);
  g_clear_pointer(&ui.arch_choices, g_ptr_array_unref);
  g_clear_pointer(&ui.format_choices, g_ptr_array_unref);
  g_clear_pointer(&ui.presets, g_ptr_array_unref);
  g_hash_table_unref(ui.custom_checked);
  g_free(ui.platform);
  g_free(ui.arch);
  g_free(ui.format);
  g_free(ui.base_dir);
  g_free(ui.result_path);
  return code;
}
