<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import AccountMenu from "./AccountMenu.vue";
import BrandMark from "./BrandMark.vue";
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
const placeholder = computed(() =>
  mode.value === "setup"
    ? "Spacecraft, profiles, commands, settings…"
    : "Spacecraft, telemetry, commands…",
);
</script>

<template>
  <header
    class="flex h-[56px] flex-none flex-nowrap items-stretch border-b border-hairline bg-chrome md:h-auto md:min-h-[52px] md:flex-wrap"
  >
    <MobileHeaderBar v-if="small && mobileHeader" :header="mobileHeader" />
    <template v-else>
      <BrandMark />
      <ScopeSwitcher :scope="scope" />
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
      <div v-else class="flex-1" />
      <LinkStatus />
      <!-- Mode-specific status from features, composed in App.vue: Ops fleet tag / next AOS,
           Setup config revision. -->
      <slot v-if="mode === 'ops' && mission" name="status" />
      <!-- Below 768 the staged bar carries the revision, so the top row stays one line (ux #2). -->
      <div v-if="mode === 'setup' && mission" class="flex max-md:hidden">
        <slot name="setup-status" />
      </div>
      <ClockCluster />
      <AccountMenu />
    </template>
  </header>
</template>
