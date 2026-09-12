<script setup>
import { computed } from "vue";
import { AccountMenu as ShellAccount, navigateAttrs } from "../../../auth-and-navigation";
import UtcClock from "../../../shell/UtcClock.vue";
import OpsNavRail from "./OpsNavRail.vue";
import OpsContextRail from "./OpsContextRail.vue";
import { opsNavigation } from "./navigation";
import { contextRail, contextSections } from "./context";
const props = defineProps({ context: { type: Object, required: true } });
const nav = computed(() => opsNavigation(props.context));
const sections = computed(() => contextSections(props.context));
const posture = computed(() => {
  const counts = props.context.fleet_health?.normalized_state_counts;
  return !counts
    ? { label: "Posture unavailable", class: "text-base-content/45" }
    : counts.red
      ? { label: `${counts.red} Critical`, class: "bg-error/20 text-error" }
      : counts.yellow
        ? { label: `${counts.yellow} Warning`, class: "bg-warning/20 text-warning" }
        : { label: "Nominal", class: "text-success" };
});
</script>
<template>
  <div class="h-screen flex flex-col overflow-hidden bg-base-100">
    <header
      id="ops-workspace-header"
      class="grid shrink-0 grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1 border-b border-primary/20 bg-base-200 px-3 py-1.5 hud-grid md:h-10 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto_auto] md:py-0"
    >
      <a
        id="ops-mission-link"
        v-bind="navigateAttrs(`/missions/${encodeURIComponent(context.mission.mission_id)}`)"
        class="col-start-1 row-start-1 flex min-w-0 items-center gap-2 text-base-content/60 hover:text-base-content"
      >
        <span class="hero-arrow-left h-3.5 w-3.5 shrink-0"></span>
        <span class="min-w-0">
          <span class="block truncate text-sm font-bold text-base-content">{{
            context.mission.display_name
          }}</span>
          <span class="block truncate font-mono text-[10px] text-base-content/60">{{
            context.mission.slug
          }}</span>
        </span>
      </a>
      <div
        id="ops-status-line"
        class="col-span-2 row-start-2 flex items-center justify-between gap-3 md:contents"
      >
        <div
          id="ops-urgent-posture"
          class="flex min-w-0 flex-1 items-center md:col-start-2 md:row-start-1 md:justify-center"
        >
          <span
            :class="[
              'truncate font-mono text-xs uppercase tracking-wide px-2 py-0.5',
              posture.class,
            ]"
            >{{ posture.label }}</span
          >
        </div>
        <div
          id="ops-clock-and-connection"
          class="flex shrink-0 items-center justify-end gap-3 md:col-start-3 md:row-start-1"
        >
          <UtcClock
            id="ops-utc-clock"
            class="whitespace-nowrap font-mono text-xs text-base-content/70 tabular-nums"
          />
          <span
            id="ops-conn-ok"
            class="h-2 w-2 shrink-0 rounded-full bg-success"
            title="Connected"
            phx-connected='[["show",{}]]'
            phx-disconnected='[["hide",{}]]'
          ></span>
          <span
            id="ops-conn-lost"
            class="hidden h-2 w-2 shrink-0 rounded-full bg-error motion-safe:animate-pulse"
            title="Connection lost"
            phx-disconnected='[["show",{}]]'
            phx-connected='[["hide",{}]]'
          ></span>
        </div>
      </div>
      <div
        id="ops-account-controls"
        class="col-start-2 row-start-1 justify-self-end md:col-start-4"
      >
        <ShellAccount id="account-ops" :context="context" />
      </div>
    </header>
    <div class="flex flex-1 min-h-0">
      <OpsNavRail v-bind="nav" />
      <main class="flex-1 min-w-0 flex flex-col overflow-hidden">
        <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
          <div id="application-content" class="contents"><slot /></div>
        </div>
        <details
          v-if="context.dock_surfaces.length"
          id="ops-application-dock"
          open
          class="group shrink-0 border-t border-primary/25 bg-base-200/80"
        >
          <summary class="flex h-8 cursor-pointer items-center px-3 hud-label">
            Operations dock
          </summary>
          <nav aria-label="Application dock surfaces" class="flex gap-2 px-3 py-2">
            <span
              v-for="surface in context.dock_surfaces"
              :key="surface.id"
              :data-application-key="surface.application_key"
              :data-surface-id="surface.surface_id"
              class="text-xs"
              >{{ surface.label }}</span
            >
          </nav>
          <div class="h-40 flex items-center justify-center text-sm text-base-content/45">
            The application surface is registered with the Ops host.
          </div>
        </details>
      </main>
      <OpsContextRail :rail="contextRail" :sections="sections" />
    </div>
  </div>
</template>
