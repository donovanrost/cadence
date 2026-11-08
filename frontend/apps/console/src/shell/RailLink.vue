<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";

/** Count is omitted (not zero) when it can't be computed. */
defineProps<{
  to: RouteLocationRaw;
  index: string;
  label: string;
  active: boolean;
  count?: string | undefined;
  countTone?: "crit" | "live" | undefined;
}>();
</script>

<template>
  <RouterLink
    :to="to"
    :aria-current="active ? 'page' : undefined"
    :title="label"
    class="flex h-[38px] items-center gap-2.5 border-l-2 px-3 font-display text-base font-semibold tracking-tag uppercase no-underline"
    :class="
      active
        ? 'border-readout bg-raised text-readout'
        : 'border-transparent text-text-3 hover:bg-raised hover:text-readout'
    "
  >
    <span class="w-4 font-mono text-2xs font-medium text-text-4">{{ index }}</span>
    <span class="max-console:sr-only">{{ label }}</span>
    <span
      v-if="count"
      class="ml-auto font-mono max-console:hidden text-xs font-medium tracking-normal"
      :class="
        countTone === 'crit'
          ? 'text-crit-text'
          : countTone === 'live'
            ? 'text-readout'
            : 'text-text-4'
      "
      >{{ count }}</span
    >
  </RouterLink>
</template>
