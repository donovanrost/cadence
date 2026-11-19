<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApSelect, focusAfterRemove } from "@/ui";
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
// a11y A5: Remove leg takes itself; land on the next leg's Remove, else the rule's Add leg.
const box = ref<HTMLElement | null>(null);
function removeLeg(i: number) {
  legs.value = legs.value.filter((_, j) => j !== i);
  void focusAfterRemove(box.value, "[data-remove-leg]", i, () =>
    // The rule's own fieldset (each leg's group sits inside it, below this box).
    box.value?.closest("fieldset")?.querySelector<HTMLElement>("[data-add-leg]"),
  );
}
</script>

<template>
  <div ref="box" class="contents">
    <!-- a11y B7 (#313, mms-ux): each leg is a group named "Leg 2", so its Direction and Role keep
      their visible labels; the remove button is named "Remove leg 2" (its visible word first). -->
    <fieldset
      v-for="(leg, i) in legs"
      :key="i"
      class="m-0 flex min-w-0 flex-wrap items-end gap-3 border-0 p-0"
    >
      <legend class="sr-only">Leg {{ i + 1 }}</legend>
      <div class="w-40">
        <ApSelect
          :model-value="leg.direction"
          label="Direction"
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
      <ApButton
        size="compact"
        variant="ghost"
        data-remove-leg
        :aria-label="`Remove leg ${i + 1}`"
        @click="removeLeg(i)"
        >Remove leg</ApButton
      >
    </fieldset>
  </div>
</template>
