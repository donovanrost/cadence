<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import AccountMenu from "./AccountMenu.vue";
import BrandMark from "./BrandMark.vue";
import ClockCluster from "./ClockCluster.vue";
import LinkStatus from "./LinkStatus.vue";
import ModeSwitch from "./ModeSwitch.vue";
import QueryTrigger from "./QueryTrigger.vue";
import ScopeSwitcher from "./ScopeSwitcher.vue";
import { usePalette } from "./palette.ts";
import type { ConsoleScope } from "./scope.ts";

const props = defineProps<{ scope: ConsoleScope }>();
const route = useRoute();
const palette = usePalette();
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
    <!-- Ops fleet status tag / next AOS: provided by features through App.vue's topbar-status slot. -->
    <slot v-if="mode === 'ops' && mission" name="status" />
    <ClockCluster />
    <AccountMenu />
  </header>
</template>
