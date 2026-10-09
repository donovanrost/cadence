<script setup lang="ts">
/**
 * A Heroicon from the vendored set. Decorative unless `label` is given, in
 * which case it is announced as an image.
 */
withDefaults(
  defineProps<{
    name: `hero-${string}`;
    size?: "xs" | "sm" | "md" | "lg";
    label?: string;
  }>(),
  { size: "sm" },
);
const sizes = { xs: "h-3.5 w-3.5", sm: "h-4 w-4", md: "h-5 w-5", lg: "h-6 w-6" };
</script>

<template>
  <span
    :class="[name, sizes[size], 'shrink-0']"
    :role="label ? 'img' : undefined"
    :aria-label="label"
    :aria-hidden="label ? undefined : 'true'"
  ></span>
</template>
