<script setup lang="ts">
import { ApSegmented, ApSelect } from "@/ui";

/** Audit log filters: kind, mission, and (from People › person) one actor with "Show everyone". */
defineProps<{
  kind: string;
  kindOptions: readonly Readonly<{ value: string; label: string }>[];
  missionOptions: readonly Readonly<{ value: string; label: string }>[];
  actorName: string | null;
}>();
defineEmits<{ kind: [value: string] }>();
const missionId = defineModel<string>("missionId", { required: true });
</script>

<template>
  <div class="flex flex-wrap items-end gap-3">
    <ApSegmented
      :model-value="kind"
      label="Kind"
      :options="kindOptions"
      @update:model-value="$emit('kind', $event)"
    />
    <ApSelect v-model="missionId" label="Mission" :options="missionOptions" />
    <p v-if="actorName" class="m-0 pb-2 text-md text-text-2">
      Only {{ actorName }}'s events ·
      <RouterLink :to="{ name: 'org.audit' }" class="text-readout hover:underline"
        >Show everyone</RouterLink
      >
    </p>
  </div>
</template>
