<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApButton, ApChip, ApField } from "@/ui";
import type { WidgetFields } from "./contracts.ts";
import { searchObservables } from "./observables.ts";

/**
 * Points bound to a widget: chosen ids as removable chips, and a search to add more. The search
 * sends the sheet's whole form (D8), so results follow the widget's source and spacecraft.
 */
const props = defineProps<{
  missionId: MissionId;
  dashboardId: string;
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
const add = (id: string) => {
  if (!full.value) model.value = [...model.value, id];
};
</script>

<template>
  <div class="flex flex-col gap-2">
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
    <ul v-if="results.length" class="m-0 flex max-h-56 list-none flex-col overflow-auto p-0">
      <li v-for="o in results" :key="o.id">
        <ApButton variant="ghost" size="compact" class="w-full justify-start" @click="add(o.id)">
          <span class="font-mono normal-case tracking-normal">{{ o.id }}</span>
          <span v-if="o.label" class="ml-2 normal-case tracking-normal text-text-3">{{
            o.label
          }}</span>
        </ApButton>
      </li>
    </ul>
  </div>
</template>
