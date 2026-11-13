<script setup lang="ts">
import { ApSegmented, ApSelect } from "@/ui";

/** Audit log filters: actor, mission, kind (SettingsAuditProviders.md). */
defineProps<{
  actor: string;
  actorOptions: readonly Readonly<{ value: string; label: string }>[];
  kind: string;
  kindOptions: readonly Readonly<{ value: string; label: string }>[];
  missionOptions: readonly Readonly<{ value: string; label: string }>[];
}>();
defineEmits<{ kind: [value: string]; actor: [value: string] }>();
const missionId = defineModel<string>("missionId", { required: true });
</script>

<template>
  <div class="flex flex-wrap items-end gap-3">
    <ApSelect
      :model-value="actor"
      label="Actor"
      :options="actorOptions"
      @update:model-value="$emit('actor', $event)"
    />
    <ApSelect v-model="missionId" label="Mission" :options="missionOptions" />
    <ApSegmented
      :model-value="kind"
      label="Kind"
      :options="kindOptions"
      @update:model-value="$emit('kind', $event)"
    />
  </div>
</template>
