<script setup lang="ts">
import { computed, watch } from "vue";
import { useRoute } from "vue-router";
import NotFoundScreen from "./NotFoundScreen.vue";
import OpsRail from "./OpsRail.vue";
import SetupRail from "./SetupRail.vue";
import TopBar from "./TopBar.vue";
import { rememberMission } from "./last-mission.ts";
import { bindPaletteShortcut } from "./palette.ts";
import { useConsoleScope } from "./scope.ts";

const route = useRoute();
const scope = useConsoleScope();
bindPaletteShortcut();

const mode = computed(() => route.meta.mode ?? "account");
const missionScope = computed(() => (scope.value.kind === "mission" ? scope.value : null));
const orgSlug = computed(() =>
  scope.value.kind === "mission" || scope.value.kind === "organization"
    ? scope.value.organization.slug
    : null,
);
const unknownScope = computed(() => {
  const s = scope.value;
  if (s.kind === "unknown-organization")
    return `There is no organization “${s.slug}” you can open.`;
  if (s.kind === "unknown-mission")
    return `${s.organization.name} has no mission “${s.slug}” you can open.`;
  return null;
});
/** Ops screens fit the viewport and scroll their panes; reading views scroll main. */
const consoleLayout = computed(() => mode.value === "ops");

watch(
  missionScope,
  (s) => {
    if (s) rememberMission({ org: s.organization.slug, mission: s.mission.slug });
  },
  { immediate: true },
);

watch(
  () => [route.meta.title, missionScope.value?.mission.name] as const,
  ([title, mission]) => {
    document.title = [title, mission, "Cadence"].filter(Boolean).join(" · ");
  },
  { immediate: true },
);
</script>

<template>
  <div class="flex h-screen flex-col overflow-hidden">
    <a
      href="#main"
      class="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:bg-action focus:px-3 focus:py-2 focus:text-on-action"
      >Skip to content</a
    >
    <TopBar :scope="scope" />
    <div class="flex min-h-0 flex-1">
      <OpsRail
        v-if="mode === 'ops' && missionScope"
        :org="missionScope.organization.slug"
        :mission="missionScope.mission.slug"
      />
      <SetupRail
        v-else-if="mode === 'setup' && orgSlug"
        :org="orgSlug"
        :mission="missionScope?.mission.slug ?? null"
      />
      <main
        id="main"
        tabindex="-1"
        class="flex min-w-0 flex-1 flex-col"
        :class="
          consoleLayout ? 'gap-3 overflow-hidden px-5 py-3.5' : 'gap-4 overflow-auto px-6 pt-5 pb-6'
        "
      >
        <NotFoundScreen v-if="unknownScope" :sentence="unknownScope" />
        <RouterView v-else />
      </main>
    </div>
  </div>
</template>
