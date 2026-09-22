#include <cassert>
#include <initializer_list>
#include <utility>

#include <gio/gio.h>

#include "../fractional_scaling.h"

namespace {

GVariant* LogicalMonitors(std::initializer_list<std::pair<double, bool>> monitors) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a(iidub)"));
  for (const auto& [scale, primary] : monitors) {
    g_variant_builder_add(&builder, "(iidub)", 0, 0, scale, 0, primary);
  }
  return g_variant_ref_sink(g_variant_builder_end(&builder));
}

}  // namespace

int main() {
  assert(IsMutterWaylandSession("wayland-0", "GNOME"));
  assert(IsMutterWaylandSession("wayland-0", "ubuntu:GNOME"));
  assert(!IsMutterWaylandSession(nullptr, "GNOME"));
  assert(!IsMutterWaylandSession("wayland-0", "KDE"));
  assert(!HasExplicitGtkScale(nullptr, nullptr));
  assert(HasExplicitGtkScale("2", nullptr));
  assert(HasExplicitGtkScale(nullptr, "0.5"));

  g_autoptr(GVariant) fractional = LogicalMonitors({{1.25, true}});
  g_autoptr(GVariant) matching =
      LogicalMonitors({{1.25, true}, {1.25, false}});
  g_autoptr(GVariant) mixed = LogicalMonitors({{1.25, true}, {1.0, false}});
  g_autoptr(GVariant) different =
      LogicalMonitors({{1.25, true}, {1.5, false}});
  g_autoptr(GVariant) no_primary = LogicalMonitors({{1.25, false}});
  g_autoptr(GVariant) integer = LogicalMonitors({{2.0, true}});

  assert(ShouldEnableFractionalGtkScaling(fractional));
  assert(ShouldEnableFractionalGtkScaling(matching));
  assert(!ShouldEnableFractionalGtkScaling(mixed));
  assert(!ShouldEnableFractionalGtkScaling(different));
  assert(!ShouldEnableFractionalGtkScaling(no_primary));
  assert(!ShouldEnableFractionalGtkScaling(integer));
  assert(!ShouldEnableFractionalGtkScaling(g_variant_new_string("invalid")));
}
