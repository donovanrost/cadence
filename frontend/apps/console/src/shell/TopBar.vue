<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import AccountMenu from "./AccountMenu.vue";
import BrandMark from "./BrandMark.vue";
import ClockCluster from "./ClockCluster.vue";
import ModeSwitch from "./ModeSwitch.vue";
import QueryTrigger from "./QueryTrigger.vue";
import ScopeSwitcher from "./ScopeSwitcher.vue";
import type { ConsoleScope } from "./scope.ts";

const props = defineProps<{ scope: ConsoleScope }>();
const route = useRoute();
const mode = computed(() => route.meta.mode ?? "ops");
const mission = computed(() => (props.scope.kind === "mission" ? props.scope : null));
const placeholder = computed(() =>
  mode.value === "setup"
    ? "Spacecraft, profiles, commands, settings…"
    : "Spacecraft, telemetry, commands…",
);
</script>

<template>
  <header
    class="flex min-h-[52px] flex-none flex-wrap items-stretch border-b border-hairline bg-chrome"
  >
    <BrandMark />
    <ScopeSwitcher :scope="scope" />
    <ModeSwitch
      v-if="mission && mode !== 'account'"
      :mode="mode"
      :org="mission.organization.slug"
      :mission="mission.mission.slug"
    />
    <QueryTrigger v-if="mission" :placeholder="placeholder" />
    <!-- Ops fleet status tag and next-AOS countdown mount here once their live data exists. -->
    <slot name="status" />
    <ClockCluster />
    <AccountMenu />
  </header>
</template>
