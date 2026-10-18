<script setup lang="ts">
import { buttonClasses, type ButtonSize, type ButtonVariant } from "./button-recipe";

/** Navigation that looks like a button: a real link, so open-in-new-tab and copy-link work. */
withDefaults(defineProps<{ href: string; variant?: ButtonVariant; size?: ButtonSize }>(), {
  variant: "secondary",
  size: "md",
});
</script>

<template>
  <a :href="href" :class="[...buttonClasses(variant, size), 'gap-1']"><slot /></a>
</template>
