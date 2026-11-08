<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, ApField, ApPanel, ApSegmented, type ApSegment } from "@/ui";
import { useDraft } from "./context.ts";
import type { Draft, FieldErrors } from "./draft.ts";

/** A3 Orbit & routing. Plane and slot are spacecraft metadata today (plan gap). */
const { draft, set, proposal } = useDraft();

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
      <ApCallout tone="info">
        Routing moves to the profile (each profile's rules generate routes for its spacecraft).
        Until that lands, add routing rules for new spacecraft in Comms &amp; routing after creating
        them.
      </ApCallout>
    </div>
  </ApPanel>
</template>
