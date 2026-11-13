<script setup lang="ts">
import { computed } from "vue";
import type { RouteLocationRaw } from "vue-router";
import type { SpacecraftTab } from "@/shell";
import { ApButton, ApEmptyState, ApPanel } from "@/ui";

/**
 * Spacecraft tabs other than Investigate (Investigate.md [temporary], DECISIONS #64): an empty
 * state that links to the existing page for this spacecraft, until each tab is built.
 */
const props = defineProps<{
  tab: Exclude<SpacecraftTab, "investigate">;
  sc: Readonly<{ id: string; scid: number; name: string }>;
}>();

const TABS: Readonly<
  Record<
    Exclude<SpacecraftTab, "investigate">,
    (sc: typeof props.sc) => {
      title: string;
      label: string;
      sentence: string;
      to: RouteLocationRaw;
    }
  >
> = {
  telemetry: (sc) => ({
    title: "Telemetry",
    label: "Open Telemetry",
    sentence: `Telemetry plots any of ${sc.name}'s points over time.`,
    to: { name: "ops.telemetry", query: { sc: String(sc.scid) } },
  }),
  uplink: () => ({
    title: "Uplink",
    label: "Open Commands",
    sentence: "Commands lists every request and its uplink, including this spacecraft's.",
    to: { name: "ops.commands" },
  }),
  passes: () => ({
    title: "Passes",
    label: "Open Contacts",
    sentence: "Contacts shows the pass schedule by spacecraft.",
    to: { name: "ops.contacts", query: { view: "spacecraft" } },
  }),
  configuration: (sc) => ({
    title: "Configuration",
    label: "Open in Setup",
    sentence: `Setup holds ${sc.name}'s configuration and its profile.`,
    to: { name: "setup.spacecraft.one", params: { spacecraftId: sc.id } },
  }),
  history: (sc) => ({
    title: "History",
    label: "Open Timeline",
    sentence: `Timeline lists the mission's events, ${sc.name}'s among them.`,
    to: { name: "ops.timeline", query: { sc: String(sc.scid) } },
  }),
};
const view = computed(() => TABS[props.tab](props.sc));
</script>

<template>
  <ApPanel index="B1" :title="view?.title ?? tab" flush class="flex-none">
    <ApEmptyState
      state="off"
      headline="Not built yet in the new console"
      :sentence="view?.sentence ?? 'Use the existing pages for this until it ships.'"
    >
      <ApButton v-if="view" size="compact" :to="view.to">{{ view.label }}</ApButton>
    </ApEmptyState>
  </ApPanel>
</template>
