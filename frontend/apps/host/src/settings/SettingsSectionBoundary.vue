<script setup lang="ts">
import { computed, onErrorCaptured, ref } from "vue";
import {
  readSettingsSectionDefinition,
  type SettingsContext,
  type SettingsSectionDefinition,
  type SettingsSectionPort,
} from "@cadence/plugin-sdk/settings";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import { useLazyPage } from "../shell/module-pages/lazy-pages";
import { settingsSections } from "./contributions";
const props = defineProps<{
  section: SettingsSectionDefinition;
  snapshot: unknown;
  context: SettingsContext;
  canEdit: boolean;
  port: SettingsSectionPort;
}>();
const crashed = ref(false);
const loaded = useLazyPage(
  () => props.section.id,
  settingsSections,
  () => {
    crashed.value = true;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const admitted = computed(() => {
  const state = loaded.state.value;
  if (state.kind !== "ready") return null;
  try {
    const metadata = readSettingsSectionDefinition(state.value);
    return JSON.stringify(metadata) === JSON.stringify(props.section) &&
      metadata.scopes.includes(props.context.scope)
      ? state.value.component
      : null;
  } catch {
    return null;
  }
});
function retry() {
  crashed.value = false;
  loaded.reload();
}
</script>
<template>
  <p v-if="loaded.state.value.kind === 'loading'" role="status">Loading settings…</p>
  <section v-else-if="crashed || !admitted" class="settings-section-unavailable" role="alert">
    <h3>{{ section.title }} settings are unavailable</h3>
    <p>Your saved values are retained. Other settings are available from the section navigation.</p>
    <CadenceButton size="sm" @click="retry">Retry loading</CadenceButton>
  </section>
  <component
    v-else
    :is="admitted"
    :snapshot="snapshot"
    :context="context"
    :can-edit="canEdit"
    :port="port"
  >
    <template #history><slot name="history" /></template>
  </component>
</template>
<style scoped>
.settings-section-unavailable {
  padding: 24px;
  border: 1px solid var(--border-default);
  border-radius: var(--radius-md);
  background: var(--surface-elevated);
}
h3 {
  margin: 0;
}
p {
  margin: 12px 0;
  color: var(--text-subtle);
}
</style>
