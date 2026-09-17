<script setup lang="ts">
defineProps<{ label: string; trail: string; muted?: boolean }>();
</script>
<template>
  <div class="cadence-setting-source" :class="{ 'is-muted': muted }">
    <span
      :class="[
        muted ? 'hero-lock-closed' : 'hero-arrow-down-on-square',
        'cadence-setting-source__icon',
      ]"
      aria-hidden="true"
    />
    <div>
      <strong>{{ label }}</strong
      ><span>{{ trail }}</span>
    </div>
    <slot />
  </div>
</template>
<style scoped>
.cadence-setting-source {
  display: flex;
  align-items: center;
  gap: 12px;
  border-left: 2px solid var(--color-action);
  padding: 12px 14px;
  background: var(--surface-elevated);
  border-radius: 0 4px 4px 0;
}
.cadence-setting-source__icon {
  display: block;
  flex: none;
  width: 15px;
  height: 15px;
  color: var(--color-action);
}
.cadence-setting-source > div {
  flex: 1;
  min-width: 0;
}
strong {
  display: block;
  color: var(--text-bright);
  font: 550 11px/1.6 var(--font-sans);
}
div > span:not(.cadence-setting-source__icon) {
  display: block;
  font: 10px/1.8 var(--font-mono);
  color: var(--text-subtle);
  margin-top: 3px;
}
.is-muted {
  border-color: var(--text-subtle);
}
.is-muted .cadence-setting-source__icon {
  color: var(--text-subtle);
}
@media (width < 600px) {
  .cadence-setting-source {
    flex-wrap: wrap;
  }
}
</style>
