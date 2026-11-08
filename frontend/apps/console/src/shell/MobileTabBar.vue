<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { usePalette } from "./palette.ts";

/** Below 768px: on-call tabs (Mobile.md, J6). Counts join when their live data exists. */
defineProps<{ org: string; mission: string }>();
const route = useRoute();
const palette = usePalette();

const goPolls = computed(() => route.name === "ops.commands" && route.query.awaiting === "me");
const tabClass = (active: boolean) => [
  "flex min-h-12 flex-1 cursor-pointer items-center justify-center border-0 bg-transparent font-display text-xs font-semibold tracking-btn uppercase no-underline",
  active
    ? "bg-raised text-readout shadow-[inset_0_2px_0_var(--color-readout)]"
    : "text-text-3 hover:text-readout",
];
</script>

<template>
  <nav
    aria-label="On-call tabs"
    class="flex flex-none border-t border-hairline bg-chrome pb-[env(safe-area-inset-bottom)] md:hidden"
  >
    <RouterLink
      :to="{ name: 'ops.now', params: { org, mission } }"
      :aria-current="route.meta.nav === 'now' ? 'page' : undefined"
      :class="tabClass(route.meta.nav === 'now')"
      >Now</RouterLink
    >
    <RouterLink
      :to="{ name: 'ops.alarms', params: { org, mission } }"
      :aria-current="route.meta.nav === 'alarms' ? 'page' : undefined"
      :class="tabClass(route.meta.nav === 'alarms')"
      >Alarms</RouterLink
    >
    <RouterLink
      :to="{ name: 'ops.commands', params: { org, mission }, query: { awaiting: 'me' } }"
      :aria-current="goPolls ? 'page' : undefined"
      :class="tabClass(goPolls)"
      >GO polls</RouterLink
    >
    <button
      v-if="palette.available.value"
      type="button"
      :class="tabClass(palette.open.value)"
      @click="palette.show"
    >
      Search
    </button>
  </nav>
</template>
