<script setup lang="ts">
/**
 * Screen heading: label line + the screen's single h1 + optional right side (meta / actions).
 * `title` is required (plain text for fallbacks); the `title` slot may enrich the h1, e.g. a mono id.
 */
withDefaults(
  defineProps<{ label?: string | undefined; title: string; size?: "console" | "reading" }>(),
  {
    size: "console",
  },
);
</script>

<template>
  <section class="flex flex-none flex-wrap items-end justify-between gap-4">
    <div class="flex flex-col gap-1.5">
      <p v-if="label" class="ap-label text-readout">{{ label }}</p>
      <div class="flex flex-wrap items-center gap-3.5">
        <h1
          class="m-0 font-display leading-none font-semibold tracking-head uppercase"
          :class="size === 'console' ? 'text-3xl' : 'text-4xl'"
        >
          <slot name="title">{{ title }}</slot>
        </h1>
        <slot name="status" />
      </div>
      <slot name="subtitle" />
    </div>
    <slot />
  </section>
</template>
