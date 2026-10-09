<script setup lang="ts">
import CadenceIcon from "./CadenceIcon.vue";

/** An icon-only control. `label` is required: icon buttons have no visible name. */
withDefaults(
  defineProps<{
    icon: `hero-${string}`;
    label: string;
    disabled?: boolean;
    tone?: "neutral" | "danger";
    type?: "button" | "submit";
  }>(),
  { disabled: false, tone: "neutral", type: "button" },
);
</script>

<template>
  <button
    :type="type"
    class="cadence-icon-button"
    :class="[
      tone === 'danger' ? 'text-error' : '',
      'disabled:pointer-events-none disabled:opacity-40',
    ]"
    :disabled="disabled"
    :aria-label="label"
    :title="label"
  >
    <CadenceIcon :name="icon" />
  </button>
</template>
