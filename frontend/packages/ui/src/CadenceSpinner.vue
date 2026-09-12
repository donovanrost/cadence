<script setup lang="ts">
withDefaults(
  defineProps<{
    label?: string;
    size?: "sm" | "md";
  }>(),
  {
    size: "md",
  },
);
</script>

<template>
  <span
    :class="['loading loading-spinner', size === 'sm' ? 'loading-sm' : 'loading-md']"
    :role="label ? 'status' : undefined"
    :aria-label="label"
    :aria-hidden="label ? undefined : true"
  ></span>
</template>
