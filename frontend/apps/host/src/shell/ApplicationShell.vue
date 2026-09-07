<script setup>
import { computed } from "vue";
import AuthLayoutBrand from "./AuthLayoutBrand.vue";
import ShellNavigation from "./ShellNavigation.vue";
import ShellAccount from "./ShellAccount.vue";
import OpsNavRail from "./OpsNavRail.vue";
import OpsContextRail from "./OpsContextRail.vue";
import UtcClock from "./UtcClock.vue";
import { navigateAttrs, opsNavigation } from "./shell-navigation";
import { contextRail, contextSections } from "./shell-context";
const props = defineProps({
  managedPage: Boolean,
  variant: { type: String, required: true },
  context: { type: Object, required: true },
});
const nav = computed(() => (props.variant === "ops" ? opsNavigation(props.context) : null));
const sections = computed(() => (props.variant === "ops" ? contextSections(props.context) : []));
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
  <div
    v-if="variant === 'auth'"
    class="min-h-screen flex flex-col items-center justify-center px-4 py-12"
  >
    <div class="w-full max-w-sm space-y-6">
      <AuthLayoutBrand class="text-center" />
      <div id="application-content" class="contents"><slot /></div>
    </div>
  </div>
  <div v-else-if="variant === 'ops'" class="h-screen flex flex-col overflow-hidden bg-base-100">
    <header
      class="h-10 shrink-0 flex items-center gap-3 px-3 border-b border-primary/20 bg-base-200 hud-grid"
    >
      <a
        v-bind="navigateAttrs(`/missions/${encodeURIComponent(context.mission.mission_id)}`)"
        class="flex items-center gap-2 min-w-0 text-base-content/60 hover:text-base-content"
        ><span class="hero-arrow-left h-3.5 w-3.5 shrink-0"></span
        ><span class="text-sm font-bold text-base-content truncate">{{
          context.mission.display_name
        }}</span
        ><span class="font-mono text-xs text-base-content/60">{{ context.mission.slug }}</span></a
      >
      <div id="ops-urgent-posture" class="flex-1 flex items-center justify-center gap-2 min-w-0">
        <span :class="['font-mono text-xs uppercase tracking-wide px-2 py-0.5', posture.class]">{{
          posture.label
        }}</span>
      </div>
      <UtcClock id="ops-utc-clock" class="font-mono text-xs text-base-content/70 tabular-nums" />
      <span
        id="ops-conn-ok"
        class="h-2 w-2 rounded-full bg-success"
        title="Connected"
        phx-connected='[["show",{}]]'
        phx-disconnected='[["hide",{}]]'
      ></span>
      <span
        id="ops-conn-lost"
        class="hidden h-2 w-2 rounded-full bg-error motion-safe:animate-pulse"
        title="Connection lost"
        phx-disconnected='[["show",{}]]'
        phx-connected='[["hide",{}]]'
      ></span>
      <ShellAccount id="account-ops" :context="context" />
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
  <div
    v-else-if="variant === 'sidebar' || variant === 'mission_sidebar'"
    class="drawer lg:drawer-open"
  >
    <input
      id="sidebar-drawer"
      type="checkbox"
      class="drawer-toggle"
      aria-label="Navigation drawer"
    />
    <div class="drawer-content flex flex-col">
      <header class="lg:hidden flex items-center justify-between p-4 border-b border-base-300">
        <label for="sidebar-drawer" aria-label="Open navigation" class="btn btn-ghost btn-sm"
          ><span class="hero-bars-3 h-5 w-5"></span></label
        ><span class="flex-1 text-center font-semibold text-sm tracking-wider uppercase"
          >Cadence</span
        ><ShellAccount id="account-mobile" :context="context" />
      </header>
      <header
        class="hidden lg:flex items-center justify-end gap-3 px-4 h-10 border-b border-primary/20 bg-base-200 hud-grid shrink-0"
      >
        <ShellAccount id="account-desktop" :context="context" />
      </header>
      <main class="flex-1 overflow-y-auto bg-base-100">
        <div :class="managedPage ? 'contents' : 'p-6'">
          <div id="application-content" class="contents"><slot /></div>
        </div>
      </main>
    </div>
    <div class="drawer-side">
      <ShellNavigation :context="context" :mission="variant === 'mission_sidebar'" />
    </div>
  </div>
  <div v-else class="min-h-screen flex flex-col bg-base-100">
    <header
      class="flex items-center justify-between px-4 h-12 border-b border-primary/20 bg-base-200 hud-grid"
    >
      <a v-bind="navigateAttrs('/')" class="flex items-center gap-2 text-primary"
        ><span>◆</span><span class="text-xs font-bold tracking-[0.15em]">CADENCE</span></a
      ><ShellAccount id="account-user" :context="context" />
    </header>
    <main class="flex-1 overflow-y-auto" :class="!managedPage && 'p-6'">
      <div id="application-content" class="contents"><slot /></div>
    </main>
  </div>
</template>
