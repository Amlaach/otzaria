/* Otzaria Download Assistant for Linux (docs/download_assistant.md). */
#include <gtk/gtk.h>
#include <locale.h>
#include <stdio.h>

#include "otz_common.h"
#include "ui.h"

static gboolean self_test = FALSE;
static char *dev_owner = NULL;
static char *dev_manifest = NULL;
static char *dev_auto_preset = NULL;
static char *dev_platform = NULL;
static char *dev_output = NULL;

static GOptionEntry entries[] = {
    {"self-test", 0, 0, G_OPTION_ARG_NONE, &self_test,
     "Open the window briefly and exit (CI smoke test)", NULL},
    {"dev-owner", 0, 0, G_OPTION_ARG_STRING, &dev_owner,
     "DEV ONLY: GitHub organization to trust instead of Otzaria (fork testing)",
     "OWNER"},
    {"dev-manifest", 0, 0, G_OPTION_ARG_FILENAME, &dev_manifest,
     "DEV ONLY: read the release manifest from a local file", "FILE"},
    {"dev-auto-preset", 0, 0, G_OPTION_ARG_STRING, &dev_auto_preset,
     "DEV ONLY: walk the pages with their defaults, pick this preset "
     "(full/basic/update), print a report and exit",
     "ID"},
    {"dev-platform", 0, 0, G_OPTION_ARG_STRING, &dev_platform,
     "DEV ONLY: preselect this target platform", "PLATFORM"},
    {"dev-output", 0, 0, G_OPTION_ARG_FILENAME, &dev_output,
     "DEV ONLY: output folder", "DIR"},
    {NULL},
};

static void show_missing_tls(void) {
  GtkWidget *dialog = gtk_message_dialog_new(
      NULL, 0, GTK_MESSAGE_ERROR, GTK_BUTTONS_NONE, "%s",
      "לא ניתן להתחבר באופן מאובטח לאתר ההורדות, כי במחשב הזה חסר רכיב מערכת.");
  gtk_message_dialog_format_secondary_text(
      GTK_MESSAGE_DIALOG(dialog),
      "יש להתקין את החבילה glib-networking (למשל: sudo apt install "
      "glib-networking) ולהפעיל את המסייע מחדש.");
  gtk_dialog_add_button(GTK_DIALOG(dialog), "סגור", GTK_RESPONSE_CLOSE);
  gtk_window_set_title(GTK_WINDOW(dialog), "מסייע הורדה לאוצריא");
  gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);
}

int main(int argc, char **argv) {
  setlocale(LC_ALL, "");
  g_autoptr(GOptionContext) context =
      g_option_context_new("- Otzaria Download Assistant");
  g_option_context_add_main_entries(context, entries, NULL);
  g_option_context_add_group(context, gtk_get_option_group(TRUE));
  g_autoptr(GError) error = NULL;
  if (!g_option_context_parse(context, &argc, &argv, &error)) {
    g_printerr("%s\n", error->message);
    return 2;
  }
  if (dev_owner != NULL) otz_set_allowed_owner(dev_owner);

  gtk_widget_set_default_direction(GTK_TEXT_DIR_RTL);
  gboolean tls = g_tls_backend_supports_tls(g_tls_backend_get_default());
  if (self_test) {
    printf("self-test: tls=%s tag=%s\n", tls ? "yes" : "no",
           otz_embedded_release_tag());
    fflush(stdout);
  } else if (!tls) {
    show_missing_tls();
    return 1;
  }

  OtzUiOptions options = {
      .self_test = self_test,
      .dev_manifest = dev_manifest,
      .dev_auto_preset = dev_auto_preset,
      .dev_platform = dev_platform,
      .dev_output = dev_output,
  };
  int code = otz_ui_run(&options);
  if (self_test && code == 0) printf("self-test: ok\n");
  return code;
}
