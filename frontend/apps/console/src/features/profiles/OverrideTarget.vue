<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchSpacecraftDirectory } from "@/features/spacecraft/index.ts";
import { ApRemote, ApSelect } from "@/ui";

/** Add override's target: a spacecraft on this profile and the field it overrides. */
const props = defineProps<{
  missionId: MissionId;
  profile: Readonly<{ id: string; name: string }>;
  fieldOptions: readonly Readonly<{ value: string; label: string }>[];
}>();
const spacecraft = defineModel<Readonly<{ id: string; name: string }> | null>("spacecraft", {
  required: true,
});
const path = defineModel<string>("path", { required: true });
const missionId = computed(() => props.missionId);
const { state, refetch } = useRemoteQuery(missionId, fetchSpacecraftDirectory);
const options = computed(() =>
  state.value.status === "ready"
    ? state.value.value.spacecraft
        .filter((r) => r.profile?.id === props.profile.id)
        .map((r) => ({ value: r.id, label: r.name }))
    : [],
);
const spacecraftId = computed({
  get: () => spacecraft.value?.id ?? "",
  set: (id: string) => {
    const o = options.value.find((x) => x.value === id);
    spacecraft.value = o ? { id: o.value, name: o.label } : null;
  },
});
</script>

<template>
  <ApRemote :state="state" loading-label="Loading spacecraft…" @retry="refetch">
    <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
      <ApSelect
        v-model="spacecraftId"
        label="Spacecraft"
        mono
        required
        placeholder="Choose…"
        :options="options"
        :hint="`${options.length} on ${profile.name}`"
      />
      <ApSelect v-model="path" label="Field" :options="fieldOptions" />
    </div>
  </ApRemote>
</template>
