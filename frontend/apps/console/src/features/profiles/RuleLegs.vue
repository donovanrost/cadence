<script setup lang="ts">
import { ApButton, ApSelect } from "@/ui";
import { directions, roles, type RuleDraft } from "./rulesDraft.ts";

/** A rule's legs: direction + role per leg, each removable. */
type Leg = RuleDraft["legs"][number];
const legs = defineModel<Leg[]>({ required: true });
const directionOptions = directions.map((d) => ({
  value: d,
  label: d === "downlink" ? "Downlink" : "Uplink",
}));
const roleOptions = roles.map((r) => ({ value: r, label: r[0]?.toUpperCase() + r.slice(1) }));
function setLeg(i: number, p: Partial<Leg>) {
  legs.value = legs.value.map((l, j) => (j === i ? { ...l, ...p } : l));
}
</script>

<template>
  <div v-for="(leg, i) in legs" :key="i" class="flex flex-wrap items-end gap-3">
    <div class="w-40">
      <ApSelect
        :model-value="leg.direction"
        :label="`Leg ${i + 1} direction`"
        :options="directionOptions"
        @update:model-value="$event && setLeg(i, { direction: $event })"
      />
    </div>
    <div class="w-40">
      <ApSelect
        :model-value="leg.role"
        label="Role"
        :options="roleOptions"
        @update:model-value="$event && setLeg(i, { role: $event })"
      />
    </div>
    <ApButton size="compact" variant="ghost" @click="legs = legs.filter((_, j) => j !== i)"
      >Remove leg</ApButton
    >
  </div>
</template>
