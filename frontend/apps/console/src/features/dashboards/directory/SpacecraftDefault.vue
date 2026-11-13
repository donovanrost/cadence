<script setup lang="ts">
import { computed } from "vue";
import { useMissionScope } from "@/shell";
import { useFleet } from "@/features/fleet/index.ts";
import { ApSegmented, ApSelect } from "@/ui";
import type { NewSpacecraft as SpacecraftChoice } from "./api.ts";

/**
 * New dashboard's Spacecraft (ux): one spacecraft (its default scope), chosen when viewing, or the
 * whole fleet. D4 (76ff5edc) stores a default only for `fixed`; the other two set none.
 */
defineProps<{ error?: string | null | undefined }>();
const model = defineModel<SpacecraftChoice>({ required: true });
const scope = useMissionScope();
const fleet = useFleet(
  computed(() => scope.value.mission.id),
  { live: false },
);
const options = computed(() =>
  fleet.state.value.status === "ready"
    ? fleet.state.value.value.spacecraft.map((s) => ({ value: s.id, label: s.name }))
    : [],
);
const mode = computed({
  get: () => model.value.mode,
  set: (m: SpacecraftChoice["mode"]) =>
    (model.value =
      m === "fixed"
        ? { mode: "fixed", spacecraft_id: options.value[0]?.value ?? "" }
        : { mode: m }),
});
const picked = computed({
  get: () => (model.value.mode === "fixed" ? model.value.spacecraft_id : ""),
  set: (id: string) => (model.value = { mode: "fixed", spacecraft_id: id }),
});
</script>

<template>
  <ApSegmented
    v-model="mode"
    label="Spacecraft"
    :options="[
      { value: 'fixed', label: 'One spacecraft' },
      { value: 'context', label: 'Chosen when viewing' },
      { value: 'fleet', label: 'Whole fleet' },
    ]"
  />
  <ApSelect
    v-if="mode === 'fixed'"
    v-model="picked"
    label="Which spacecraft"
    mono
    placeholder="Choose a spacecraft"
    :options="options"
    :error="error"
  />
</template>
