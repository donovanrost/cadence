<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";
import { useNow } from "./lib/clock.ts";
import { formatClock } from "./lib/format.ts";

/**
 * Header for takeover screens (commanding, multi-step wizards): close/back · mono context line
 * over the title · progress (`steps` slot, e.g. ApStationBar or ApStepBar) · clocks · actions.
 * The title is an h1 only when the screen has no other (`titleAs`).
 */
withDefaults(
  defineProps<{
    title: string;
    context?: string | undefined;
    close: RouteLocationRaw;
    closeLabel?: string | undefined;
    titleAs?: "h1" | "p" | undefined;
  }>(),
  { closeLabel: "Close", titleAs: "p" },
);
const now = useNow();
</script>

<template>
  <div
    class="flex min-h-[52px] flex-none flex-wrap items-stretch border-b border-hairline bg-chrome"
  >
    <RouterLink
      :to="close"
      :aria-label="closeLabel"
      class="flex w-[52px] items-center justify-center border-r border-hairline text-readout hover:bg-raised"
    >
      <svg
        aria-hidden="true"
        width="14"
        height="14"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2.5"
      >
        <path d="M6 6l12 12M18 6 6 18" />
      </svg>
    </RouterLink>
    <div class="flex flex-col justify-center gap-0.5 border-r border-hairline px-[18px] py-1.5">
      <span v-if="context" class="font-mono text-xs text-text-4 uppercase">{{ context }}</span>
      <component
        :is="titleAs"
        class="m-0 font-display text-[19px] leading-tight font-bold tracking-[.14em] uppercase"
      >
        <slot name="title">{{ title }}</slot>
      </component>
    </div>
    <slot name="steps" />
    <div class="ml-auto flex items-center gap-5 px-[18px] font-mono text-md">
      <span class="flex gap-[0.6em]"
        ><span class="text-text-4">UTC</span
        ><time :datetime="now.toISOString()" class="tabular">{{ formatClock(now) }}</time></span
      >
      <slot name="clocks" />
    </div>
    <div v-if="$slots.actions" class="flex items-center gap-2 border-l border-hairline px-4">
      <slot name="actions" />
    </div>
  </div>
</template>
