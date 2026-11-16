<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import AccountMenu from "./AccountMenu.vue";
import BrandMark from "./BrandMark.vue";
import AdminChip from "./AdminChip.vue";
import ClockCluster from "./ClockCluster.vue";
import LinkStatus from "./LinkStatus.vue";
import MobileHeaderBar from "./MobileHeaderBar.vue";
import { useCurrentMobileHeader } from "./mobile-header.ts";
import { useSmallScreen } from "./viewport.ts";
import ModeSwitch from "./ModeSwitch.vue";
import QueryTrigger from "./QueryTrigger.vue";
import ScopeSwitcher from "./ScopeSwitcher.vue";
import { usePalette } from "./palette.ts";
import type { ConsoleScope } from "./scope.ts";
import { TopBarLevel, useTopBarFit } from "./topbar-fit.ts";

const props = defineProps<{ scope: ConsoleScope }>();
const route = useRoute();
const palette = usePalette();
const small = useSmallScreen();
const mobileHeader = useCurrentMobileHeader();
/** Takeover screens (multi-step wizards) belong to Setup: the switch keeps SETUP lit. */
const mode = computed(() => {
  const raw = route.meta.mode ?? "ops";
  return raw === "takeover" ? "setup" : raw;
});
const mission = computed(() => (props.scope.kind === "mission" ? props.scope : null));
/**
 * From 768 the bar fits by giving way in ux's order (topbar-fit.ts), never by clipping: every item
 * keeps its width except the query trigger (data-topbar-flex), and only the last step wraps.
 */
const header = ref<HTMLElement | null>(null);
const { level } = useTopBarFit(
  header,
  computed(() => !small.value),
);
const placeholder = computed(() =>
  mode.value === "setup"
    ? "Spacecraft, profiles, commands, settings…"
    : "Spacecraft, telemetry, commands…",
);
</script>

<template>
  <header
    ref="header"
    :data-topbar-level="level"
    class="flex h-[56px] flex-none flex-nowrap items-stretch border-b border-hairline bg-chrome md:h-auto md:min-h-[52px] md:[&>*:not([data-topbar-flex])]:flex-none"
    :class="level >= TopBarLevel.wrap ? 'md:flex-wrap' : ''"
  >
    <MobileHeaderBar v-if="small && mobileHeader" :header="mobileHeader" />
    <template v-else>
      <BrandMark />
      <!-- L7 (ux Admin.md): platform admin has no org or mission scope to switch. -->
      <p
        v-if="mode === 'admin'"
        class="m-0 flex items-center border-r border-hairline px-4 font-mono text-sm font-semibold tracking-tag text-caution-text uppercase md:px-[18px]"
      >
        Platform admin
      </p>
      <ScopeSwitcher v-else :scope="scope" />
      <ModeSwitch
        v-if="mission && mode !== 'account'"
        class="max-md:hidden"
        :mode="mode"
        :org="mission.organization.slug"
        :mission="mission.mission.slug"
      />
      <QueryTrigger
        v-if="mission && palette.available.value"
        class="max-md:hidden"
        :placeholder="placeholder"
      />
      <div v-else class="flex-1" data-topbar-flex />
      <LinkStatus />
      <!-- Status from features, composed in App.vue: the fleet posture (both modes, ux IA §Top bar),
           then Setup's config revision. -->
      <slot v-if="(mode === 'ops' || mode === 'setup') && mission" name="status" />
      <!-- Below 768 the staged bar carries the revision, so the top row stays one line (ux #2). -->
      <div v-if="mode === 'setup' && mission" class="flex max-md:hidden">
        <slot name="setup-status" />
      </div>
      <AdminChip />
      <ClockCluster />
      <AccountMenu />
    </template>
  </header>
</template>
