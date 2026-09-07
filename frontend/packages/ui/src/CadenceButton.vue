<script setup lang="ts">
import CadenceSpinner from "./CadenceSpinner.vue";
withDefaults(
  defineProps<{
    disabled?: boolean;
    loading?: boolean;
    size?: "xs" | "sm" | "md" | "lg";
    type?: "button" | "submit" | "reset";
    variant?: "primary" | "secondary" | "quiet" | "danger" | "outline";
  }>(),
  { disabled: false, loading: false, size: "md", type: "button", variant: "secondary" },
);
const variants = {
  primary: "btn-primary",
  secondary: "",
  quiet: "btn-ghost",
  danger: "btn-error",
  outline: "btn-outline",
};
const sizes = { xs: "btn-xs", sm: "btn-sm", md: "", lg: "btn-lg" };
</script>
<template>
  <button
    :class="['btn', variants[variant], sizes[size]]"
    :type="type"
    :disabled="disabled || loading"
    :aria-busy="loading || undefined"
  >
    <CadenceSpinner v-if="loading" size="sm" />
    <slot />
  </button>
</template>
