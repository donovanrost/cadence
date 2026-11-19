<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApButton, ApField } from "@/ui";
import { fetchDirectory } from "../directory/api.ts";
import { MAX_DASHBOARDS } from "./api.ts";

/** The playlist's dashboards in order: ↑ ↓ remove, and a search (D1) to add more. */
type Item = Readonly<{ id: string; name: string; archived: boolean }>;
const props = defineProps<{ missionId: MissionId }>();
const model = defineModel<readonly Item[]>({ required: true });
const q = ref("");
const key = computed(() =>
  q.value.trim().length >= 2 ? JSON.stringify([props.missionId, q.value.trim()]) : null,
);
const search = useRemoteQuery(key, (_k, signal) =>
  fetchDirectory(
    props.missionId,
    { q: q.value.trim(), tags: [], starred: false, archived: false, sort: "name", page: 1 },
    signal,
  ),
);
const results = computed(() =>
  search.state.value.status === "ready"
    ? search.state.value.value.dashboards
        .filter((d) => !model.value.some((m) => m.id === d.id))
        .slice(0, 8)
    : [],
);
function move(index: number, by: -1 | 1) {
  const next = [...model.value];
  const [item] = next.splice(index, 1);
  if (item) next.splice(index + by, 0, item);
  model.value = next;
}
const add = (d: { id: string; name: string }) => {
  if (model.value.length < MAX_DASHBOARDS)
    model.value = [...model.value, { id: d.id, name: d.name, archived: false }];
};
</script>

<template>
  <ol class="m-0 flex list-none flex-col p-0" aria-label="Dashboards in order">
    <li
      v-for="(item, i) in model"
      :key="item.id"
      class="flex items-center gap-2 border-b border-hairline-faint py-1.5"
    >
      <span class="w-6 font-mono text-sm text-text-4">{{ i + 1 }}</span>
      <span class="min-w-0 flex-1 truncate text-md text-readout"
        >{{ item.name
        }}<span v-if="item.archived" class="ml-2 text-xs uppercase tracking-tag text-text-4"
          >Archived · remove to save</span
        ></span
      >
      <ApButton
        size="compact"
        variant="ghost"
        :disabled="i === 0"
        disabled-reason="Already first."
        :aria-label="`Move ${item.name} up`"
        @click="move(i, -1)"
        >↑</ApButton
      >
      <ApButton
        size="compact"
        variant="ghost"
        :disabled="i === model.length - 1"
        disabled-reason="Already last."
        :aria-label="`Move ${item.name} down`"
        @click="move(i, 1)"
        >↓</ApButton
      >
      <ApButton
        size="compact"
        variant="ghost"
        :aria-label="`Remove ${item.name}`"
        @click="model = model.filter((m) => m.id !== item.id)"
        >Remove</ApButton
      >
    </li>
  </ol>
  <ApField
    v-model="q"
    type="search"
    label="Add dashboards"
    :disabled="model.length >= MAX_DASHBOARDS"
    :hint="
      model.length >= MAX_DASHBOARDS
        ? `A playlist holds up to ${MAX_DASHBOARDS}.`
        : 'Type at least 2 characters.'
    "
  />
  <ul v-if="results.length" class="m-0 flex list-none flex-col p-0">
    <li v-for="d in results" :key="d.id">
      <ApButton variant="ghost" size="compact" class="w-full justify-start" @click="add(d)"
        ><span class="normal-case tracking-normal">{{ d.name }}</span></ApButton
      >
    </li>
  </ul>
</template>
