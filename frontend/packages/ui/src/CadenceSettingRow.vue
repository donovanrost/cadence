<script setup lang="ts">
import { useId } from "vue";
defineProps<{ label: string; description?: string }>();
const labelId = useId();
const descriptionId = useId();
</script>

<template>
  <div
    class="cadence-setting-row"
    role="group"
    :aria-labelledby="labelId"
    :aria-describedby="description ? descriptionId : undefined"
  >
    <div class="cadence-setting-row__label">
      <div :id="labelId">{{ label }}</div>
      <p v-if="description" :id="descriptionId">{{ description }}</p>
      <div v-if="$slots.source" class="cadence-setting-row__source"><slot name="source" /></div>
    </div>
    <div class="cadence-setting-row__control">
      <slot :label-id="labelId" :description-id="descriptionId" />
    </div>
    <div v-if="$slots.detail" class="cadence-setting-row__detail"><slot name="detail" /></div>
  </div>
</template>

<style scoped>
.cadence-setting-row {
  display: grid;
  grid-template-columns: minmax(170px, 0.9fr) minmax(200px, 1.1fr);
  column-gap: 28px;
  row-gap: 16px;
  padding-block: 22px;
}
.cadence-setting-row + .cadence-setting-row {
  border-top: 1px solid var(--border-subtle);
}
.cadence-setting-row__label {
  color: var(--text-bright);
  font: 550 12px/1.5 var(--font-sans);
}
.cadence-setting-row__label p {
  margin: 6px 0 0;
  color: var(--text-subtle);
  font-weight: 400;
  line-height: 1.7;
}
.cadence-setting-row__source {
  margin-top: 12px;
  font-size: 11px;
  font-weight: 400;
  color: var(--text-subtle);
}
.cadence-setting-row__control {
  min-width: 0;
}
.cadence-setting-row__detail {
  grid-column: 1 / -1;
  min-width: 0;
}
@media (width < 760px) {
  .cadence-setting-row {
    grid-template-columns: minmax(0, 1fr);
    gap: 14px;
    padding-block: 18px;
  }
}
</style>
