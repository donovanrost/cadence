<script setup lang="ts">
import { useId } from "vue";
defineProps<{ title: string; description?: string }>();
const headingId = useId();
</script>

<template>
  <section class="cadence-settings-section" :aria-labelledby="headingId">
    <header class="cadence-settings-section__header">
      <div>
        <h3 :id="headingId">{{ title }}</h3>
        <p v-if="description">{{ description }}</p>
      </div>
      <div v-if="$slots.status"><slot name="status" /></div>
    </header>
    <div class="cadence-settings-section__body"><slot /></div>
    <footer v-if="$slots.footer" class="cadence-settings-section__footer">
      <slot name="footer" />
    </footer>
  </section>
</template>

<style scoped>
.cadence-settings-section {
  min-width: 0;
  border: 1px solid var(--border-default);
  border-radius: var(--radius-md);
  background: var(--surface-base);
}
.cadence-settings-section__header {
  display: flex;
  justify-content: space-between;
  align-items: start;
  gap: var(--space-4);
  padding: 18px 20px;
  border-bottom: 1px solid var(--border-subtle);
}
h3 {
  margin: 0;
  color: var(--text-bright);
  font: 600 13px/1.5 var(--font-sans);
}
p {
  margin: 5px 0 0;
  color: var(--text-subtle);
  font: 12px/1.6 var(--font-sans);
  max-width: 64ch;
}
.cadence-settings-section__body {
  padding-inline: 20px;
}
.cadence-settings-section__footer {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: 12px 20px;
  background: var(--elevation-sunken);
  border-top: 1px solid var(--border-subtle);
  color: var(--text-subtle);
  font: 11px/1.5 var(--font-sans);
}
@media (width < 600px) {
  .cadence-settings-section__header {
    padding: 15px;
  }
  .cadence-settings-section__body {
    padding-inline: 15px;
  }
  .cadence-settings-section__footer {
    padding: 12px 15px;
  }
}
</style>
