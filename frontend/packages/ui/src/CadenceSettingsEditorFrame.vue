<script setup lang="ts">
import CadenceButton from "./CadenceButton.vue";
defineProps<{
  dirty: boolean;
  busy: boolean;
  saveDisabled: boolean;
  canKeepChanges: boolean;
  conflict: boolean;
  uncertain: boolean;
  message: string;
}>();
defineEmits<{ save: []; discard: []; refresh: []; keepChanges: [] }>();
</script>
<template>
  <div class="cadence-settings-editor">
    <div class="cadence-settings-editor__body">
      <div v-if="conflict" role="status" class="cadence-settings-editor__conflict">
        <strong>Saved settings changed</strong><slot name="conflict" />
        <div class="cadence-settings-editor__actions">
          <CadenceButton
            size="sm"
            :disabled="busy || uncertain || !canKeepChanges"
            @click="$emit('keepChanges')"
            >Keep my changes</CadenceButton
          >
          <CadenceButton size="sm" variant="quiet" :disabled="busy" @click="$emit('discard')"
            >Use latest values</CadenceButton
          >
        </div>
      </div>
      <slot />
      <div
        v-if="dirty"
        class="cadence-settings-editor__save"
        role="region"
        aria-label="Unsaved settings"
      >
        <strong>Unsaved changes</strong>
        <div class="cadence-settings-editor__actions">
          <CadenceButton size="sm" variant="quiet" :disabled="busy" @click="$emit('discard')"
            >Discard</CadenceButton
          >
          <CadenceButton
            size="sm"
            variant="primary"
            :loading="busy"
            :disabled="saveDisabled"
            @click="$emit('save')"
            >Save changes</CadenceButton
          >
        </div>
      </div>
      <p v-if="message" role="status" aria-live="polite">{{ message }}</p>
      <CadenceButton v-if="uncertain" size="sm" :loading="busy" @click="$emit('refresh')"
        >Check saved values</CadenceButton
      >
    </div>
    <aside class="cadence-settings-editor__context" aria-label="Settings context">
      <slot name="context" /><slot name="history" />
    </aside>
  </div>
</template>
<style scoped>
.cadence-settings-editor {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 206px;
  gap: 26px;
  align-items: start;
  color: var(--text-bright);
  font: 12px/1.6 var(--font-sans);
}
.cadence-settings-editor__body {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 20px;
}
.cadence-settings-editor__context {
  border-left: 1px solid var(--border-subtle);
  padding-left: 22px;
  display: flex;
  flex-direction: column;
  gap: 24px;
}
.cadence-settings-editor__conflict {
  padding: 16px;
  border: 1px solid var(--color-warning);
  border-radius: var(--radius-md);
  background: var(--surface-elevated);
}
.cadence-settings-editor__actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.cadence-settings-editor__save {
  position: sticky;
  bottom: 16px;
  display: flex;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  align-items: center;
  padding: 14px 16px;
  background: var(--surface-elevated);
  border: 1px solid var(--border-strong);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-floating);
  z-index: 1;
}
p {
  margin: 0;
  color: var(--text-subtle);
}
@media (width < 1200px) {
  .cadence-settings-editor {
    grid-template-columns: minmax(0, 1fr);
  }
  .cadence-settings-editor__context {
    border-left: 0;
    border-top: 1px solid var(--border-subtle);
    padding: 20px 0 0;
  }
}
</style>
