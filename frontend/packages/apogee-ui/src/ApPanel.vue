<script setup lang="ts">
/**
 * Every surface is a panel: zero radius, hairline border, indexed header with meta on the right.
 * `pane` fills a console grid cell and scrolls its body; the page never scrolls.
 */
import { ref } from "vue";
import { useScrollable } from "./lib/scrollable.ts";

withDefaults(
  defineProps<{
    /** Index code in reading order, e.g. `A1`. */
    index?: string | undefined;
    title?: string | undefined;
    /** Right-aligned mono meta, e.g. `6 OPEN · SORTED BY URGENCY`. Use the `meta` slot for links. */
    meta?: string | undefined;
    variant?: "default" | "emphasized" | undefined;
    alert?: "crit" | "caution" | undefined;
    pane?: boolean | undefined;
    /** Drop body padding (tables, lists). */
    flush?: boolean | undefined;
    headingLevel?: 2 | 3 | undefined;
  }>(),
  { variant: "default", pane: false, flush: false, headingLevel: 2 },
);
/** A pane body that scrolls is a named, focusable group (axe scrollable-region-focusable). */
const body = ref<HTMLElement | null>(null);
const scrolls = useScrollable(body);
</script>

<template>
  <section
    class="relative border"
    :class="[
      variant === 'emphasized' ? 'bg-raised border-line' : 'bg-panel border-hairline',
      pane ? 'flex min-h-0 flex-col overflow-hidden' : '',
    ]"
  >
    <header
      v-if="title || $slots.header"
      class="flex flex-none flex-wrap items-center gap-3 border-b border-hairline px-4 py-2.5"
    >
      <span
        v-if="index"
        class="font-mono text-xs font-medium"
        :class="
          alert === 'crit'
            ? 'text-crit-text'
            : alert === 'caution'
              ? 'text-caution-text'
              : 'text-text-4'
        "
        >{{ index }}</span
      >
      <component
        :is="`h${headingLevel}`"
        v-if="title"
        class="m-0 font-display text-base font-semibold tracking-title text-text-2 uppercase"
        >{{ title }}</component
      >
      <slot name="header" />
      <span
        v-if="meta || $slots.meta"
        class="ml-auto font-mono text-xs font-medium text-text-4 uppercase"
      >
        <slot name="meta">{{ meta }}</slot>
      </span>
    </header>
    <div
      ref="body"
      :class="[pane ? 'min-h-0 flex-1 overflow-auto' : '', flush ? '' : 'p-4']"
      :tabindex="pane && scrolls ? 0 : undefined"
      :role="pane && scrolls ? 'group' : undefined"
      :aria-label="pane && scrolls ? title : undefined"
    >
      <slot />
    </div>
  </section>
</template>
