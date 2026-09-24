/* The GtkAssistant flow (docs/download_assistant.md, "בחירת היעד"). */
#pragma once

#include <glib.h>

typedef struct {
  gboolean self_test;
  /* Dev only: see main.c --help. */
  const char *dev_manifest;
  const char *dev_auto_preset;
  const char *dev_platform;
  const char *dev_output;
} OtzUiOptions;

/* Runs the assistant; returns the process exit code. */
int otz_ui_run(const OtzUiOptions *options);
