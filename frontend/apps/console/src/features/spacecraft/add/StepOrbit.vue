<script setup lang="ts">
import { computed } from "vue";
import { useMissionScope } from "@/shell";
import { ApField, ApPanel, ApSegmented, type ApSegment } from "@/ui";
import { useDraft } from "./context.ts";
import type { Draft, FieldErrors } from "./draft.ts";
import RoutingSummary from "./RoutingSummary.vue";

/** A3 Orbit & routing. Plane and slot are spacecraft metadata today (plan gap). */
const { draft, set, proposal } = useDraft();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
/** The batch size: the generated rows once identity is valid, else the typed count. */
const count = computed(() => {
  const p = proposal();
  if (p.status === "ready") return p.report.rows.length;
  const n = Number(draft.count);
  return Number.isInteger(n) && n > 0 ? n : 1;
});

const modes = computed((): readonly ApSegment<Draft["planeMode"]>[] => [
  ...(draft.source === "manifest"
    ? [{ value: "manifest" as const, label: "From manifest" }]
    : [{ value: "fill" as const, label: "Fill planes" }]),
  { value: "none", label: "Not now" },
]);
const mode = computed({
  get: () => draft.planeMode,
  set: (value: Draft["planeMode"]) => set("planeMode", value),
});
const errors = computed((): FieldErrors => {
  const p = proposal();
  return p.status === "incomplete" && p.step === "orbit" ? p.errors : {};
});
</script>

<template>
  <ApPanel index="A3" title="Orbit & routing">
    <div class="flex flex-col gap-4">
      <p class="m-0 text-md text-text-3">
        Planes show on the constellation view and the fleet matrix.
      </p>
      <ApSegmented v-model="mode" :options="modes" label="Plane assignment" />
      <div v-if="draft.planeMode === 'fill'" class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <ApField
          :model-value="draft.firstPlane"
          label="First plane"
          inputmode="numeric"
          mono
          :error="errors.firstPlane ?? null"
          @update:model-value="set('firstPlane', $event)"
        />
        <ApField
          :model-value="draft.perPlane"
          label="Spacecraft per plane"
          inputmode="numeric"
          mono
          :error="errors.perPlane ?? null"
          @update:model-value="set('perPlane', $event)"
        />
      </div>
      <RoutingSummary
        v-if="draft.source === 'profile' && draft.profileId"
        :mission-id="missionId"
        :profile-id="draft.profileId"
        :count="count"
      />
      <p v-else class="m-0 text-md text-text-3">
        Each spacecraft gets the routes its profile's rules generate.
      </p>
    </div>
  </ApPanel>
</template>
