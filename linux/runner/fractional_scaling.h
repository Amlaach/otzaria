#ifndef RUNNER_FRACTIONAL_SCALING_H_
#define RUNNER_FRACTIONAL_SCALING_H_

#include <gio/gio.h>

bool IsMutterWaylandSession(const char* wayland_display,
                            const char* current_desktop);
bool HasExplicitGtkScale(const char* gdk_scale, const char* gdk_dpi_scale);
bool ShouldEnableFractionalGtkScaling(GVariant* logical_monitors);
void ConfigureFractionalGtkScaling();

#endif  // RUNNER_FRACTIONAL_SCALING_H_
