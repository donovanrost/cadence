<script setup lang="ts">
defineProps<{
  name: string;
  value: string;
  checked: boolean;
  label: string;
  description: string;
}>();
defineEmits<{ select: [] }>();
</script>
<template>
  <label class="cadence-radio-card" :data-selected="checked">
    <input type="radio" :name="name" :value="value" :checked="checked" @change="$emit('select')" />
    <span v-if="$slots.icon" class="cadence-radio-card__icon" aria-hidden="true"
      ><slot name="icon"
    /></span>
    <span
      ><strong>{{ label }}</strong
      ><small>{{ description }}</small></span
    >
  </label>
</template>
<style scoped>
.cadence-radio-card {
  display: flex;
  align-items: start;
  gap: 9px;
  padding: 11px;
  border: 1px solid var(--border-default);
  border-radius: var(--radius-md);
  cursor: pointer;
}
input {
  flex: none;
  margin: 3px 0 0;
  width: 13px;
  height: 13px;
  accent-color: var(--color-action);
}
.cadence-radio-card__icon {
  display: block;
  flex: none;
  width: 18px;
  height: 18px;
  color: var(--text-subtle);
}
.cadence-radio-card__icon :slotted(*) {
  display: block;
  width: 100%;
  height: 100%;
}
strong {
  display: block;
  color: var(--text-bright);
  font: 550 11px/1.6 var(--font-sans);
}
small {
  display: block;
  color: var(--text-subtle);
  font: 11px/1.6 var(--font-sans);
  margin-top: 4px;
}
[data-selected="true"] {
  background: color-mix(in srgb, var(--color-action) 6%, var(--surface-base));
  border-color: color-mix(in srgb, var(--color-action) 65%, var(--border-default));
}
[data-selected="true"] .cadence-radio-card__icon {
  color: var(--color-action);
}
.cadence-radio-card:has(input:disabled) {
  cursor: default;
}
.cadence-radio-card:has(input:focus-visible) {
  outline: 2px solid var(--border-focus);
  outline-offset: 2px;
}
</style>
