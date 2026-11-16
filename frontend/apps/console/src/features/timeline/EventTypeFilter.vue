<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref, useId, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { describeApiError, useRemoteQuery } from "@/api/index.ts";
import { useDisclosure } from "@/shell/index.ts";
import { ApButton, ApField } from "@/ui";
import { fetchRawKinds, type EventKind } from "./api.ts";
import { rawKindLabel } from "./model.ts";

/**
 * The Event type filter (§11c(C) A9b; ux decisions U71, api 4a2f470d8): a multi-select next to the
 * group toggles, in the URL as `?raw_kind=`. Options use the fold words with counts, most frequent
 * first, and list only types in the groups shown (a chosen type always stays listed). Type-ahead
 * only. `Clear filters` resets the groups, the types and the severity threshold. At most 20 types (api).
 */
const props = defineProps<{
  missionId: MissionId;
  window: Readonly<{ from: Date; to: Date }> | null;
  kinds: readonly EventKind[];
}>();
const MAX = 20;
const route = useRoute();
const router = useRouter();
const root = ref<HTMLElement | null>(null);
const { open, toggle } = useDisclosure(root);
const listId = useId();
const q = ref("");
const selected = computed(() =>
  typeof route.query["raw_kind"] === "string"
    ? route.query["raw_kind"].split(",").filter((s) => s !== "")
    : [],
);
const read = useRemoteQuery(
  computed(() =>
    props.window
      ? {
          m: props.missionId,
          from: props.window.from.toISOString(),
          to: props.window.to.toISOString(),
        }
      : null,
  ),
  (k, signal) => fetchRawKinds(k.m, { from: new Date(k.from), to: new Date(k.to) }, signal),
);
/** A failed read says so, with Retry, never 'none in this window' (fe-ops' review). */
const loadError = computed(() =>
  read.state.value.status === "failed" ? describeApiError(read.state.value.error) : null,
);
const options = computed(() => {
  const rows = read.state.value.status === "ready" ? read.state.value.value : [];
  const term = q.value.trim().toLowerCase();
  return rows
    .filter(
      (r) =>
        selected.value.includes(r.raw_kind) ||
        (r.kind !== "unrecognized" && props.kinds.includes(r.kind)),
    )
    .map((r) => ({ raw: r.raw_kind, label: `${rawKindLabel(r.raw_kind)} (${r.count})` }))
    .filter((o) => term === "" || o.label.toLowerCase().includes(term));
});
function setTypes(next: readonly string[]) {
  router
    .replace({ query: { ...route.query, raw_kind: next.length ? next.join(",") : undefined } })
    .catch((e: unknown) => console.error("Navigation failed", e));
}
const flip = (raw: string) =>
  setTypes(
    selected.value.includes(raw)
      ? selected.value.filter((s) => s !== raw)
      : [...selected.value, raw],
  );
const filtered = computed(
  () =>
    selected.value.length > 0 ||
    typeof route.query["kind"] === "string" ||
    typeof route.query["severity"] === "string",
);
function clearFilters() {
  // 'Cleared' is the full log: groups, types and the severity threshold (ux, via fe-ops).
  const { kind: _kind, raw_kind: _types, severity: _floor, ...rest } = route.query;
  router.replace({ query: rest }).catch((e: unknown) => console.error("Navigation failed", e));
}
watch(open, async (isOpen) => {
  if (!isOpen) return;
  await nextTick();
  root.value?.querySelector<HTMLElement>("input[type=search]")?.focus();
});
</script>

<template>
  <div ref="root" class="relative flex flex-wrap items-center gap-2">
    <ApButton
      size="compact"
      variant="secondary"
      :aria-expanded="open ? 'true' : 'false'"
      :aria-controls="listId"
      @click="toggle"
      >Event type{{ selected.length ? ` · ${selected.length}` : "" }}</ApButton
    >
    <ApButton v-if="filtered" size="compact" variant="ghost" @click="clearFilters"
      >Clear filters</ApButton
    >
    <div
      v-if="open"
      :id="listId"
      class="absolute top-full left-0 z-30 mt-1 flex w-[320px] flex-col gap-2 border border-line bg-raised p-3"
    >
      <ApField v-model="q" label="Find an event type" type="search" />
      <fieldset class="m-0 max-h-64 overflow-auto border-0 p-0">
        <legend class="sr-only">Event type</legend>
        <label
          v-for="o in options"
          :key="o.raw"
          class="flex min-h-11 cursor-pointer items-center gap-2 text-md text-readout"
        >
          <input
            type="checkbox"
            class="accent-[var(--color-readout)] [color-scheme:dark]"
            :checked="selected.includes(o.raw)"
            :disabled="!selected.includes(o.raw) && selected.length >= MAX"
            @change="flip(o.raw)"
          />
          {{ o.label }}
        </label>
        <p v-if="loadError" class="m-0 flex flex-wrap items-center gap-2 text-sm text-caution-text">
          Couldn't load event types: {{ loadError }}
          <ApButton size="compact" variant="secondary" @click="read.refetch">Retry</ApButton>
        </p>
        <p v-else-if="!options.length" class="m-0 text-sm text-text-3">
          {{ q.trim() ? "No event types match." : "No event types in this window." }}
        </p>
      </fieldset>
      <p v-if="selected.length >= MAX" class="m-0 text-sm text-text-3" role="status">
        Up to {{ MAX }} types at once.
      </p>
    </div>
  </div>
</template>
