<script setup lang="ts">
import CadenceSpinner from "./CadenceSpinner.vue";
import { buttonClasses, type ButtonSize, type ButtonVariant } from "./button-recipe";
withDefaults(
  defineProps<{
    disabled?: boolean;
    loading?: boolean;
    size?: ButtonSize;
    type?: "button" | "submit" | "reset";
    variant?: ButtonVariant;
  }>(),
  { disabled: false, loading: false, size: "md", type: "button", variant: "secondary" },
);
</script>
<template>
  <button
    :class="buttonClasses(variant, size)"
    :type="type"
    :disabled="disabled || loading"
    :aria-busy="loading || undefined"
  >
    <CadenceSpinner v-if="loading" size="sm" />
    <slot />
  </button>
</template>
