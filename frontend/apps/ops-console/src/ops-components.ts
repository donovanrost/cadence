import type { Component } from "vue";

const componentModules = import.meta.glob(
  ["./*.vue", "!./OpsConsoleApplication.vue", "!./StandaloneApp.vue"],
  {
    eager: true,
    import: "default",
  },
) as Record<string, Component>;

export const OPS_COMPONENTS: Record<string, Component> = Object.fromEntries(
  Object.entries(componentModules)
    .map(([path, component]) => [path.slice("./".length, -".vue".length), component]),
);

export const OPS_COMPONENT_NAMES = Object.freeze(Object.keys(OPS_COMPONENTS).sort());
