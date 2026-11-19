<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApSelect } from "@/ui";
import { SEVERITIES, SEVERITY_WORDS, type Severity } from "./filters.ts";

/**
 * ux U69 A6: the filter row above L1. Spacecraft (one) · Severity (Critical / Caution, multi);
 * By point stays in L2 and they all combine. Clear filters resets this row.
 */
const props = defineProps<{
  /** Spacecraft with alarms in the tab, each with its count (ux): 'EARENDIL-312 (3)'. */
  options: readonly { value: string; label: string }[];
  spacecraftId: string | null;
  severities: readonly Severity[];
}>();
const emit = defineEmits<{
  spacecraft: [id: string | null];
  severities: [s: Severity[]];
  clear: [];
}>();
const options = computed(() => [{ value: "", label: "Any spacecraft" }, ...props.options]);
const sc = computed({
  get: () => props.spacecraftId ?? "",
  set: (v: string) => emit("spacecraft", v || null),
});
const toggle = (s: Severity) =>
  emit(
    "severities",
    props.severities.includes(s)
      ? props.severities.filter((x) => x !== s)
      : [...props.severities, s],
  );
</script>

<template>
  <div class="flex flex-wrap items-center gap-3">
    <div class="w-48">
      <ApSelect v-model="sc" label="Spacecraft" hidden-label size="compact" :options="options" />
    </div>
    <!-- Toggle group: the same pattern as Timeline's kind filter. -->
    <div role="group" aria-label="Severity" class="flex gap-1.5">
      <button
        v-for="s in SEVERITIES"
        :key="s"
        type="button"
        class="inline-flex h-11 cursor-pointer items-center border px-3 font-display text-md font-semibold tracking-tag uppercase"
        :class="
          severities.includes(s)
            ? 'border-readout bg-raised text-readout'
            : 'border-line text-text-3 hover:text-readout'
        "
        :aria-pressed="severities.includes(s)"
        @click="toggle(s)"
      >
        {{ SEVERITY_WORDS[s] }}
      </button>
    </div>
    <ApButton
      v-if="spacecraftId !== null || severities.length"
      size="compact"
      variant="ghost"
      @click="emit('clear')"
      >Clear filters</ApButton
    >
  </div>
</template>
