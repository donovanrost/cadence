<script setup lang="ts">
import type { DashboardId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApButton, ApChip, ApField, refocusFirst } from "@/ui";
import type { WidgetFields } from "./contracts.ts";
import { searchObservables } from "./observables.ts";

/**
 * Points bound to a widget: chosen ids as removable chips, and a search to add more. The search
 * sends the sheet's whole form (D8), so results follow the widget's source and spacecraft.
 */
const props = defineProps<{
  missionId: MissionId;
  dashboardId: DashboardId;
  baseVersion: number;
  fields: WidgetFields;
  limit: number;
}>();
const model = defineModel<readonly string[]>({ required: true });
const q = ref("");
const key = computed(() =>
  q.value.trim().length >= 2
    ? JSON.stringify([
        props.missionId,
        props.dashboardId,
        props.baseVersion,
        props.fields,
        q.value.trim(),
      ])
    : null,
);
const search = useRemoteQuery(key, (_k, signal) =>
  searchObservables(
    props.missionId,
    props.dashboardId,
    { query: q.value.trim(), baseVersion: props.baseVersion, fields: props.fields },
    signal,
  ),
);
const results = computed(() =>
  search.state.value.status === "ready"
    ? search.state.value.value.observables.filter((o) => !model.value.includes(o.id))
    : [],
);
const full = computed(() => model.value.length >= props.limit);
/**
 * B6: a search that finds nothing, or fails, says so (results alone would be silent). No match is
 * a result, read politely; a failed search after the person typed is an alert (ux, #461).
 */
const noMatch = computed(() => {
  const s = search.state.value;
  return key.value !== null && s.status === "ready" && results.value.length === 0
    ? `No points to add match “${q.value.trim()}”.`
    : "";
});
const failed = computed(() =>
  key.value !== null && search.state.value.status === "failed"
    ? "Couldn't search points. Change the search to try again."
    : "",
);
/**
 * A5: the picked result leaves the list; focus goes to the next one, else the one before, else
 * the search.
 */
const root = ref<HTMLElement | null>(null);
async function add(id: string, index: number) {
  if (full.value) return;
  model.value = [...model.value, id];
  await nextTick();
  const picks = root.value?.querySelectorAll<HTMLElement>("[data-pick]") ?? [];
  const field = root.value?.querySelector<HTMLElement>('input[type="search"]:not([disabled])');
  // Full now (the search is disabled): the new chip's ×.
  const chips = root.value?.querySelectorAll<HTMLElement>("[data-ap-chip-remove]") ?? [];
  refocusFirst(picks[index], picks[index - 1], field, chips[chips.length - 1]);
}
</script>

<template>
  <div ref="root" class="flex flex-col gap-2">
    <ul
      v-if="model.length"
      class="m-0 flex list-none flex-wrap gap-1.5 p-0"
      aria-label="Bound points"
    >
      <li v-for="id in model" :key="id">
        <ApChip
          removable
          :remove-label="`Remove ${id}`"
          @remove="model = model.filter((x) => x !== id)"
          >{{ id }}</ApChip
        >
      </li>
    </ul>
    <ApField
      v-model="q"
      type="search"
      label="Add points"
      mono
      :disabled="full"
      :hint="full ? `This widget takes up to ${limit}.` : 'Type at least 2 characters.'"
    />
    <p aria-live="polite" class="m-0 text-sm text-text-3">{{ noMatch }}</p>
    <p role="alert" class="m-0 text-sm text-caution-text">{{ failed }}</p>
    <ul v-if="results.length" class="m-0 flex max-h-56 list-none flex-col overflow-auto p-0">
      <li v-for="(o, index) in results" :key="o.id">
        <ApButton
          variant="ghost"
          size="compact"
          class="w-full justify-start"
          data-pick
          @click="add(o.id, index)"
        >
          <span class="font-mono normal-case tracking-normal">{{ o.id }}</span>
          <span v-if="o.label" class="ml-2 normal-case tracking-normal text-text-3">{{
            o.label
          }}</span>
        </ApButton>
      </li>
    </ul>
  </div>
</template>
