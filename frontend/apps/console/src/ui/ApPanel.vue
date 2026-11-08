<script setup lang="ts">
/**
 * Every surface is a panel: zero radius, hairline border, indexed header with meta on the right.
 * `pane` fills a console grid cell and scrolls its body; the page never scrolls.
 */
withDefaults(
  defineProps<{
    /** Index code in reading order, e.g. `A1`. */
    index?: string;
    title?: string;
    /** Right-aligned mono meta, e.g. `6 OPEN · SORTED BY URGENCY`. Use the `meta` slot for links. */
    meta?: string;
    variant?: "default" | "emphasized";
    alert?: "crit" | "caution";
    pane?: boolean;
    /** Drop body padding (tables, lists). */
    flush?: boolean;
    headingLevel?: 2 | 3;
  }>(),
  { variant: "default", pane: false, flush: false, headingLevel: 2 },
);
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
    <div :class="[pane ? 'min-h-0 flex-1 overflow-auto' : '', flush ? '' : 'p-4']">
      <slot />
    </div>
  </section>
</template>
