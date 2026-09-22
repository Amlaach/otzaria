#include "fractional_scaling.h"

#include <cmath>
#include <cstring>

namespace {

constexpr double kScaleEpsilon = 0.001;

bool IsFractionalScale(double scale) {
  return scale > 1.0 + kScaleEpsilon && scale < 2.0 - kScaleEpsilon;
}

bool HasDesktopName(const char* current_desktop, const char* desktop) {
  if (current_desktop == nullptr) {
    return false;
  }

  const size_t desktop_length = std::strlen(desktop);
  for (const char* part = current_desktop; *part != '\0';) {
    const char* end = std::strchr(part, ':');
    const size_t length = end == nullptr ? std::strlen(part)
                                         : static_cast<size_t>(end - part);
    if (length == desktop_length &&
        g_ascii_strncasecmp(part, desktop, length) == 0) {
      return true;
    }
    if (end == nullptr) {
      break;
    }
    part = end + 1;
  }
  return false;
}

}  // namespace

bool IsMutterWaylandSession(const char* wayland_display,
                            const char* current_desktop) {
  return wayland_display != nullptr && *wayland_display != '\0' &&
         HasDesktopName(current_desktop, "GNOME");
}

bool HasExplicitGtkScale(const char* gdk_scale, const char* gdk_dpi_scale) {
  return (gdk_scale != nullptr && *gdk_scale != '\0') ||
         (gdk_dpi_scale != nullptr && *gdk_dpi_scale != '\0');
}

bool ShouldEnableFractionalGtkScaling(GVariant* logical_monitors) {
  if (logical_monitors == nullptr ||
      !g_variant_is_of_type(logical_monitors, G_VARIANT_TYPE_ARRAY)) {
    return false;
  }

  bool found_primary = false;
  double common_scale = 0.0;
  for (gsize i = 0; i < g_variant_n_children(logical_monitors); ++i) {
    g_autoptr(GVariant) monitor =
        g_variant_get_child_value(logical_monitors, i);
    if (!g_variant_is_of_type(monitor, G_VARIANT_TYPE_TUPLE) ||
        g_variant_n_children(monitor) < 5) {
      return false;
    }

    g_autoptr(GVariant) scale_value = g_variant_get_child_value(monitor, 2);
    g_autoptr(GVariant) primary_value =
        g_variant_get_child_value(monitor, 4);
    if (!g_variant_is_of_type(scale_value, G_VARIANT_TYPE_DOUBLE) ||
        !g_variant_is_of_type(primary_value, G_VARIANT_TYPE_BOOLEAN)) {
      return false;
    }

    const double scale = g_variant_get_double(scale_value);
    if (!std::isfinite(scale) || !IsFractionalScale(scale)) {
      return false;
    }
    if (i == 0) {
      common_scale = scale;
    } else if (std::abs(scale - common_scale) > kScaleEpsilon) {
      return false;
    }
    found_primary = found_primary || g_variant_get_boolean(primary_value);
  }

  return found_primary;
}

void ConfigureFractionalGtkScaling() {
  if (!IsMutterWaylandSession(g_getenv("WAYLAND_DISPLAY"),
                              g_getenv("XDG_CURRENT_DESKTOP")) ||
      HasExplicitGtkScale(g_getenv("GDK_SCALE"), g_getenv("GDK_DPI_SCALE"))) {
    return;
  }

  g_autoptr(GDBusConnection) connection =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (connection == nullptr) {
    return;
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      connection, "org.gnome.Mutter.DisplayConfig",
      "/org/gnome/Mutter/DisplayConfig", "org.gnome.Mutter.DisplayConfig",
      "GetCurrentState", nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE, 100,
      nullptr, &error);
  if (reply == nullptr || !g_variant_is_of_type(reply, G_VARIANT_TYPE_TUPLE) ||
      g_variant_n_children(reply) < 3) {
    return;
  }

  g_autoptr(GVariant) logical_monitors = g_variant_get_child_value(reply, 2);
  if (ShouldEnableFractionalGtkScaling(logical_monitors)) {
    g_setenv("GDK_SCALE", "2", FALSE);
    g_setenv("GDK_DPI_SCALE", "0.5", FALSE);
  }
}
