#include "my_application.h"

#include <gio/gio.h>
#include <glib.h>

namespace {

void configure_fractional_scaling() {
  // Flutter's GTK3 embedder receives only integer GDK scale factors. On GNOME
  // fractional scaling this can leave embedded offscreen textures at 1x and
  // make them blurry after Mutter upscales the window. Render at 2x for
  // fractional scales between 100% and 200%; Mutter then downsamples instead.
  g_autoptr(GDBusConnection) connection =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (connection == nullptr) {
    return;
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      connection, "org.gnome.Mutter.DisplayConfig",
      "/org/gnome/Mutter/DisplayConfig", "org.gnome.Mutter.DisplayConfig",
      "GetCurrentState", nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE, 1000,
      nullptr, &error);
  if (reply == nullptr || g_variant_n_children(reply) < 3) {
    return;
  }

  g_autoptr(GVariant) logical_monitors = g_variant_get_child_value(reply, 2);
  const gsize count = g_variant_n_children(logical_monitors);
  double selected_scale = 1.0;
  bool found_primary = false;

  for (gsize i = 0; i < count; ++i) {
    g_autoptr(GVariant) monitor = g_variant_get_child_value(logical_monitors, i);
    if (g_variant_n_children(monitor) < 5) {
      continue;
    }

    g_autoptr(GVariant) scale_value = g_variant_get_child_value(monitor, 2);
    g_autoptr(GVariant) primary_value = g_variant_get_child_value(monitor, 4);
    const double scale = g_variant_get_double(scale_value);
    const bool primary = g_variant_get_boolean(primary_value);

    if (primary || !found_primary) {
      selected_scale = scale;
    }
    if (primary) {
      found_primary = true;
      break;
    }
  }

  if (selected_scale > 1.0 && selected_scale < 2.0) {
    g_setenv("GDK_SCALE", "2", TRUE);
    g_setenv("GDK_DPI_SCALE", "0.5", TRUE);
  }
}

}  // namespace

int main(int argc, char** argv) {
  configure_fractional_scaling();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
