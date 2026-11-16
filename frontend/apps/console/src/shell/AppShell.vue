<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute } from "vue-router";
import MobileTabBar from "./MobileTabBar.vue";
import { ApCallout, useScrollable } from "@/ui";
import NotFoundScreen from "./NotFoundScreen.vue";
import OpsRail from "./OpsRail.vue";
import AdminRail from "./AdminRail.vue";
import SetupRail from "./SetupRail.vue";
import TopBar from "./TopBar.vue";
import { rememberMission } from "./last-mission.ts";
import { bindPaletteShortcut } from "./palette.ts";
import { useConsoleScope } from "./scope.ts";
import { canAdministerOrganization, useSession } from "./session.ts";
import { useOpsCounts } from "./counts.ts";
import { provideFleetPosture } from "./fleet-posture.ts";
import { provideRuntimeStatus } from "./runtime-status.ts";
import RuntimeBanner from "./RuntimeBanner.vue";
import { useRuntimeBanner } from "./runtime-banner.ts";
import { useAdminOrgSelect } from "./admin-org.ts";
import { useRouteFocus } from "./route-focus.ts";

const route = useRoute();
const scope = useConsoleScope();
const session = useSession();
const canAdminOrg = computed(() => {
  const s = scope.value;
  return s.kind === "mission" || s.kind === "organization"
    ? canAdministerOrganization(session, s.organization)
    : false;
});
bindPaletteShortcut();

const mode = computed(() => route.meta.mode ?? "account");
const missionScope = computed(() => (scope.value.kind === "mission" ? scope.value : null));
const orgSlug = computed(() =>
  scope.value.kind === "mission" || scope.value.kind === "organization"
    ? scope.value.organization.slug
    : null,
);
const { switching } = useAdminOrgSelect(scope, session);
const unknownScope = computed(() => {
  const s = scope.value;
  if (s.kind === "unknown-organization")
    return `There is no organization “${s.slug}” you can open.`;
  if (s.kind === "unknown-mission")
    return `${s.organization.name} has no mission “${s.slug}” you can open.`;
  return null;
});
/** Read on every mission page: the Ops rail's counts, and U38's runtime banner (Ops and Setup). */
const { counts } = useOpsCounts(computed(() => missionScope.value?.mission.id ?? null));
/** One runtime status for the banner and for features (useRuntimeStatus). */
const runtimeStatus = computed(() => (counts.value ? (counts.value.runtime ?? null) : undefined));
provideRuntimeStatus(runtimeStatus);
/** The top bar's fleet posture reads the same /counts (no second poll; ux IA §Top bar). */
provideFleetPosture(
  computed(() => (counts.value ? (counts.value.posture ?? undefined) : undefined)),
);
const runtimeBanner = useRuntimeBanner(
  runtimeStatus,
  computed(() => missionScope.value?.mission.name ?? null),
);
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
/** A scrolling main must be keyboard reachable (axe scrollable-region-focusable, qa U30 #3). */
const main = ref<HTMLElement | null>(null);
const mainScrolls = useScrollable(main);
/** After a page change: focus its heading and announce its title (a11y, lead). */
const { announcement } = useRouteFocus(main);
</script>

<template>
  <div class="flex h-screen flex-col overflow-hidden">
    <a
      href="#main"
      class="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:bg-action focus:px-3 focus:py-2 focus:text-on-action"
      >Skip to content</a
    >
    <!-- U19: takeover screens replace the top bar with their own header (TakeoverHeader
         teleports into this target, outside <main>). -->
    <div v-if="mode === 'takeover'" id="ap-takeover-header" class="contents" />
    <TopBar v-else :scope="scope">
      <template #status><slot name="topbar-status" /></template>
      <template #setup-status><slot name="topbar-setup-status" /></template>
    </TopBar>
    <RuntimeBanner v-if="runtimeBanner && missionScope" :banner="runtimeBanner" />
    <div class="flex min-h-0 flex-1">
      <OpsRail
        v-if="mode === 'ops' && missionScope"
        :org="missionScope.organization.slug"
        :mission="missionScope.mission.slug"
        :can-admin-org="canAdminOrg"
        :counts="counts"
      />
      <AdminRail v-else-if="mode === 'admin'" />
      <SetupRail
        v-else-if="mode === 'setup' && orgSlug"
        :org="orgSlug"
        :mission="missionScope?.mission.slug ?? null"
        :can-admin-org="canAdminOrg"
      />
      <div class="flex min-w-0 flex-1 flex-col">
        <main
          id="main"
          ref="main"
          :tabindex="mainScrolls ? 0 : -1"
          class="flex min-h-0 flex-1 flex-col"
          :class="
            consoleLayout
              ? 'gap-3 overflow-auto px-4 py-3 md:px-5 md:py-3.5 console:overflow-hidden'
              : 'gap-4 overflow-auto px-4 pt-4 pb-6 md:px-6 md:pt-5'
          "
        >
          <!-- The wrapper hides it: on ApCallout's root the kit's own `flex` outranks md:hidden (qa, 1440). -->
          <div v-if="mode === 'setup'" class="md:hidden">
            <ApCallout tone="info">
              Setup is designed for a larger screen. You can read here; editing works best on a
              desktop.
            </ApCallout>
          </div>
          <p v-if="switching" role="status" class="m-0 font-mono text-sm text-text-3 uppercase">
            Opening {{ switching }} as platform admin…
          </p>
          <NotFoundScreen v-else-if="unknownScope" :sentence="unknownScope" />
          <RouterView v-else />
        </main>
        <p class="sr-only" role="status" aria-live="polite">{{ announcement }}</p>
        <!-- Setup bottom bar (staged changes), composed in App.vue; stays put while main scrolls. -->
        <slot v-if="mode === 'setup' && missionScope" name="setup-footer" />
      </div>
    </div>
    <MobileTabBar
      v-if="mode === 'ops' && missionScope"
      :org="missionScope.organization.slug"
      :mission="missionScope.mission.slug"
      :counts="counts"
    />
  </div>
</template>
