<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { ApButton, ApField, ApSelect } from "@/ui";
import {
  qProblem,
  STAGE_FILTER_WORDS,
  STAGES,
  type CommandFilters,
  type Stage,
} from "./filters.ts";

/**
 * ux U72 (A5a/b): Search requests · Target · State, all in the URL; Clear filters resets them.
 * The search reaches the URL after a short pause, and never while it's over 100 characters.
 */
const props = defineProps<{
  filters: CommandFilters;
  spacecraft: readonly { id: string; name: string }[];
}>();
const emit = defineEmits<{
  q: [q: string | null];
  target: [id: string | null];
  stages: [stages: Stage[]];
  clear: [];
}>();
const text = ref(props.filters.q);
watch(
  () => props.filters.q,
  (q) => {
    if (q !== text.value.trim()) text.value = q;
  },
);
let timer: ReturnType<typeof setTimeout> | null = null;
watch(text, (t) => {
  if (timer) clearTimeout(timer);
  if (qProblem(t)) return;
  timer = setTimeout(() => emit("q", t.trim() || null), 300);
});
const targets = computed(() => [
  { value: "", label: "Any target" },
  ...props.spacecraft.map((s) => ({ value: s.id, label: s.name })),
]);
const target = computed({
  get: () => props.filters.target ?? "",
  set: (v: string) => emit("target", v || null),
});
const toggle = (s: Stage) =>
  emit(
    "stages",
    props.filters.stages.includes(s)
      ? props.filters.stages.filter((x) => x !== s)
      : [...props.filters.stages, s],
  );
const any = computed(
  () => props.filters.q !== "" || props.filters.target !== null || props.filters.stages.length > 0,
);
</script>

<template>
  <div class="flex flex-wrap items-start gap-3">
    <div class="w-64">
      <!-- The visible placeholder is short; the accessible name says what it searches (ux U72). -->
      <ApField
        v-model="text"
        type="search"
        label="Search requests by title, log entry, command or id"
        hidden-label
        placeholder="Search requests"
        :error="qProblem(text)"
      />
    </div>
    <div class="w-48">
      <ApSelect v-model="target" label="Target" hidden-label size="compact" :options="targets" />
    </div>
    <!-- Toggle group: the same pattern as Alarms' severity and Timeline's kinds. -->
    <div role="group" aria-label="State" class="flex flex-wrap gap-1.5">
      <button
        v-for="s in STAGES"
        :key="s"
        type="button"
        class="inline-flex h-11 cursor-pointer items-center border px-3 font-display text-md font-semibold tracking-tag uppercase"
        :class="
          filters.stages.includes(s)
            ? 'border-readout bg-raised text-readout'
            : 'border-line text-text-3 hover:text-readout'
        "
        :aria-pressed="filters.stages.includes(s)"
        @click="toggle(s)"
      >
        {{ STAGE_FILTER_WORDS[s] }}
      </button>
    </div>
    <ApButton v-if="any" size="compact" variant="ghost" @click="emit('clear')"
      >Clear filters</ApButton
    >
  </div>
</template>
