<script setup lang="ts">
withDefaults(
  defineProps<{
    selected: boolean;
    label: string;
    disabled?: boolean;
    layout?: "tile" | "responsive";
  }>(),
  { disabled: false, layout: "tile" },
);
</script>
<template>
  <button
    type="button"
    class="cadence-selection-tile"
    :class="{ 'cadence-selection-tile--responsive': layout === 'responsive' && !!$slots.visual }"
    :aria-pressed="selected"
    :aria-label="label"
    :disabled="disabled"
  >
    <span class="cadence-selection-tile__heading"
      ><slot name="title" /><span class="cadence-selection-tile__mark" aria-hidden="true">{{
        selected ? "✓" : ""
      }}</span></span
    >
    <span v-if="$slots.visual" class="cadence-selection-tile__visual"><slot name="visual" /></span>
    <span class="cadence-selection-tile__content"><slot /></span>
    <span v-if="$slots.footer" class="cadence-selection-tile__footer"><slot name="footer" /></span>
  </button>
</template>
<style scoped>
.cadence-selection-tile {
  display: flex;
  flex-direction: column;
  gap: calc(2.25 * var(--workspace-space, 4px));
  width: 100%;
  min-width: 0;
  padding: calc(2.5 * var(--workspace-space, 4px));
  border: 1px solid var(--border-default);
  border-radius: 4px;
  background: var(--surface-base);
  color: var(--text-bright);
  text-align: left;
  cursor: pointer;
  font: inherit;
}
.cadence-selection-tile--responsive {
  display: var(--workspace-tile-display, flex);
  grid-template-columns: var(--workspace-tile-visual-width, auto) minmax(0, 1fr);
  grid-template-areas: "heading heading" "visual content";
  align-items: stretch;
}
.cadence-selection-tile--responsive:has(.cadence-selection-tile__footer) {
  grid-template-areas: "heading heading" "visual content" "footer footer";
}
.cadence-selection-tile:hover:enabled {
  background: var(--surface-elevated);
  border-color: var(--border-strong);
}
.cadence-selection-tile[aria-pressed="true"] {
  background: color-mix(in srgb, var(--color-action) 9%, var(--surface-base));
  border-color: var(--color-action);
}
.cadence-selection-tile:focus-visible {
  outline: 2px solid var(--color-action);
  outline-offset: 2px;
}
.cadence-selection-tile:disabled {
  opacity: 0.55;
  cursor: default;
}
.cadence-selection-tile__heading {
  grid-area: heading;
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 8px;
  font-size: 11px;
  font-weight: 650;
  overflow-wrap: anywhere;
}
.cadence-selection-tile__mark {
  display: grid;
  place-items: center;
  flex: none;
  width: 14px;
  height: 14px;
  border: 1px solid var(--border-strong);
  border-radius: 3px;
  font-size: 10px;
}
[aria-pressed="true"] .cadence-selection-tile__mark {
  border-color: var(--color-action);
  background: var(--color-action);
  color: var(--surface-base);
}
.cadence-selection-tile__visual {
  grid-area: visual;
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 0;
  min-height: var(--workspace-tile-visual-height, 55px);
}
.cadence-selection-tile__content {
  grid-area: content;
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
  overflow-wrap: anywhere;
  font-size: 11px;
}
.cadence-selection-tile__footer {
  grid-area: footer;
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: auto;
  padding-top: calc(1.75 * var(--workspace-space, 4px));
  border-top: 1px solid var(--border-subtle);
  color: var(--text-subtle);
  font: 10px var(--font-mono);
}
</style>
