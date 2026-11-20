<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { announcePolite, ApButton, ApField, refocusFirst } from "@/ui";
import { fetchDirectory } from "../directory/api.ts";
import { MAX_DASHBOARDS } from "./api.ts";

/**
 * The playlist's dashboards in order: ↑ ↓ remove, and a search (D1) to add more. A5: focus stays
 * on the moved row's arrow, and goes to a neighbour when a row or a result leaves. B6: a move is
 * announced, and a search with no match or a failed one says so.
 */
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
const outcome = computed(() => {
  const s = search.state.value;
  if (key.value === null) return "";
  if (s.status === "failed") return "Couldn't search dashboards. Change the search to try again.";
  return s.status === "ready" && results.value.length === 0
    ? `No dashboards to add match “${q.value.trim()}”.`
    : "";
});
const root = ref<HTMLElement | null>(null);
const all = (selector: string) =>
  Array.from(root.value?.querySelectorAll<HTMLElement>(selector) ?? []);
const field = () => root.value?.querySelector<HTMLElement>('input[type="search"]:not([disabled])');

async function move(index: number, by: -1 | 1) {
  const next = [...model.value];
  const [item] = next.splice(index, 1);
  if (!item) return;
  next.splice(index + by, 0, item);
  model.value = next;
  await nextTick();
  // Reordering moves the row's element, which can drop focus from its arrow.
  root.value
    ?.querySelector<HTMLElement>(`[data-order="${item.id}:${by < 0 ? "up" : "down"}"]`)
    ?.focus();
  announcePolite(`${item.name} moved to ${index + by + 1} of ${next.length}.`);
}
async function remove(index: number) {
  model.value = model.value.filter((_, i) => i !== index);
  await nextTick();
  const removes = all("[data-order-remove]");
  refocusFirst(removes[index], removes[index - 1], field());
}
async function add(d: { id: string; name: string }, index: number) {
  if (model.value.length >= MAX_DASHBOARDS) return;
  model.value = [...model.value, { id: d.id, name: d.name, archived: false }];
  await nextTick();
  const picks = all("[data-pick]");
  const removes = all("[data-order-remove]");
  refocusFirst(picks[index], picks[index - 1], field(), removes[removes.length - 1]);
}
</script>

<template>
  <div ref="root" class="contents">
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
          :data-order="`${item.id}:up`"
          @click="move(i, -1)"
          >↑</ApButton
        >
        <ApButton
          size="compact"
          variant="ghost"
          :disabled="i === model.length - 1"
          disabled-reason="Already last."
          :aria-label="`Move ${item.name} down`"
          :data-order="`${item.id}:down`"
          @click="move(i, 1)"
          >↓</ApButton
        >
        <ApButton
          size="compact"
          variant="ghost"
          :aria-label="`Remove ${item.name}`"
          data-order-remove
          @click="remove(i)"
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
    <p aria-live="polite" class="m-0 text-sm text-text-3">{{ outcome }}</p>
    <ul v-if="results.length" class="m-0 flex list-none flex-col p-0">
      <li v-for="(d, index) in results" :key="d.id">
        <ApButton
          variant="ghost"
          size="compact"
          class="w-full justify-start"
          data-pick
          @click="add(d, index)"
          ><span class="normal-case tracking-normal">{{ d.name }}</span></ApButton
        >
      </li>
    </ul>
  </div>
</template>
