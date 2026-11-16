<script setup lang="ts">
import { ref } from "vue";
import type { RouteLocationRaw } from "vue-router";
import { useNow } from "./lib/clock.ts";
import { formatClock } from "./lib/format.ts";
import { useScrollable } from "./lib/scrollable.ts";

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
/** Under 768 the steps row scrolls sideways: keyboard reachable and named then (qa §6). */
const steps = ref<HTMLElement | null>(null);
const stepsScroll = useScrollable(steps);
</script>

<template>
  <header
    class="flex min-h-[52px] flex-none flex-wrap items-stretch border-b border-hairline bg-chrome md:flex-nowrap"
  >
    <!-- From 768 the row never wraps: the title block gives way (context truncates, then the
         title), so steps and clocks keep their place (ux Compose ruling 198d12ca #5). -->
    <RouterLink
      :to="close"
      :aria-label="closeLabel"
      class="flex w-[52px] flex-none items-center justify-center border-r border-hairline text-readout hover:bg-raised"
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
    <div
      class="flex min-w-0 flex-col justify-center gap-0.5 border-r border-hairline px-[18px] py-1.5 max-md:flex-1"
    >
      <span
        v-if="context"
        class="truncate font-mono text-xs text-text-4 uppercase"
        :title="context"
        >{{ context }}</span
      >
      <component
        :is="titleAs"
        class="m-0 truncate font-display text-[19px] leading-tight font-bold tracking-[.14em] uppercase"
      >
        <slot name="title">{{ title }}</slot>
      </component>
    </div>
    <!-- Under 768: one 56px row; the station bar scrolls on its own row below (U19). -->
    <div
      ref="steps"
      class="flex md:flex-none max-md:order-last max-md:w-full max-md:overflow-x-auto max-md:border-t max-md:border-hairline"
      :tabindex="stepsScroll ? 0 : undefined"
      :role="stepsScroll ? 'region' : undefined"
      :aria-label="stepsScroll ? 'Progress' : undefined"
    >
      <slot name="steps" />
    </div>
    <div class="ml-auto flex flex-none items-center gap-5 px-[18px] font-mono text-md">
      <span class="flex gap-[0.6em]"
        ><span class="text-text-4">UTC</span
        ><time :datetime="now.toISOString()" class="tabular">{{ formatClock(now) }}</time></span
      >
      <slot name="clocks" />
    </div>
    <!-- Under 768 the actions may take a row of their own and wrap there, never past the screen. -->
    <div
      v-if="$slots.actions"
      class="flex flex-none items-center gap-2 border-l border-hairline px-4 max-md:min-w-0 max-md:shrink max-md:flex-wrap max-md:py-1.5"
    >
      <slot name="actions" />
    </div>
  </header>
</template>
