<script setup lang="ts">
import { reactive } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceIconButton from "@cadence/ui/CadenceIconButton.vue";
import CadenceLinkButton from "@cadence/ui/CadenceLinkButton.vue";
import type { AdmittedHeader } from "@cadence/plugin-sdk/page-header-validation";
import type { PageAction } from "@cadence/plugin-sdk/page-header";
import HostHeaderMenu from "./HostHeaderMenu.vue";

defineProps<{ header: AdmittedHeader }>();
const running = reactive(new Set<string>());

/** Commands show pending while their promise runs; a second press is ignored. */
async function run(id: string, command: () => void | Promise<void>) {
  if (running.has(id)) return;
  running.add(id);
  try {
    await command();
  } finally {
    running.delete(id);
  }
}
const variant = (primary: boolean) => (primary ? "primary" : "quiet");
const buttons = (header: AdmittedHeader): [PageAction, boolean][] => [
  ...(header.actions ?? []).map((action): [PageAction, boolean] => [action, false]),
  ...(header.primary ? [[header.primary, true] as [PageAction, boolean]] : []),
];
</script>

<template>
  <div class="cd-page-actions">
    <CadenceIconButton
      v-if="header.refresh"
      id="host-page-refresh"
      icon="hero-arrow-path"
      label="Refresh"
      :disabled="header.refresh.pending || running.has('refresh')"
      @click="header.refresh && run('refresh', header.refresh.run)"
    />
    <template v-for="[action, primary] in buttons(header)" :key="action.id">
      <HostHeaderMenu v-if="'menu' in action" :action="action" :primary="primary" :run="run" />
      <CadenceLinkButton
        v-else-if="'href' in action"
        :id="`host-action-${action.id}`"
        :href="action.href"
        :variant="variant(primary)"
        size="sm"
      >
        <CadenceIcon v-if="action.icon" :name="action.icon" />{{ action.label }}
      </CadenceLinkButton>
      <CadenceButton
        v-else
        :id="`host-action-${action.id}`"
        :variant="variant(primary)"
        size="sm"
        :disabled="action.disabled === true"
        :loading="running.has(action.id)"
        @click="run(action.id, action.run)"
      >
        <CadenceIcon v-if="action.icon" :name="action.icon" />{{ action.label }}
      </CadenceButton>
    </template>
    <HostHeaderMenu
      v-if="header.more?.length"
      :action="{ id: 'more', label: 'More actions', menu: header.more }"
      :primary="false"
      :run="run"
      icon-only
    />
  </div>
</template>
