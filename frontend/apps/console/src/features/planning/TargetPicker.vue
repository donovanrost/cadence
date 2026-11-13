<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchProfiles } from "@/features/profiles/index.ts";
import { ApField, ApSegmented, ApSelect } from "@/ui";

/** A template target: profile, plane or listed spacecraft (CP3), kept as text until saved. */
export type TargetDraft = {
  kind: "profile" | "plane" | "spacecraft_ids";
  profileId: string;
  plane: string;
  ids: string;
};
const props = defineProps<{ missionId: MissionId; error: string | null }>();
const target = defineModel<TargetDraft>({ required: true });
const profiles = useRemoteQuery(() => props.missionId, fetchProfiles);
const profileOptions = computed(() =>
  profiles.state.value.status === "ready"
    ? profiles.state.value.value.map((p) => ({ value: p.id, label: p.name }))
    : [],
);
const patch = (p: Partial<TargetDraft>) => (target.value = { ...target.value, ...p });
</script>

<template>
  <div class="flex flex-col gap-3">
    <ApSegmented
      :model-value="target.kind"
      label="Applies to"
      :options="[
        { value: 'profile', label: 'A profile' },
        { value: 'plane', label: 'A plane' },
        { value: 'spacecraft_ids', label: 'Listed spacecraft' },
      ]"
      @update:model-value="patch({ kind: $event })"
    />
    <ApSelect
      v-if="target.kind === 'profile'"
      :model-value="target.profileId"
      label="Profile"
      placeholder="Choose a profile…"
      :options="profileOptions"
      :error="error"
      @update:model-value="patch({ profileId: $event })"
    />
    <ApField
      v-else-if="target.kind === 'plane'"
      :model-value="target.plane"
      label="Plane"
      inputmode="numeric"
      mono
      hint="Spacecraft whose plane metadata is this number."
      :error="error"
      @update:model-value="patch({ plane: $event })"
    />
    <ApField
      v-else
      :model-value="target.ids"
      label="Spacecraft ids"
      mono
      hint="Comma-separated, e.g. spacecraft-earendil-001"
      :error="error"
      @update:model-value="patch({ ids: $event })"
    />
  </div>
</template>
