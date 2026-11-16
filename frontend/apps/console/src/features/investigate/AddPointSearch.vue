<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { SpacecraftId } from "@/api/index.ts";
import { computed, nextTick, onScopeDispose, ref, watch } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { ApButton, ApField, ApRemote } from "@/ui";
import { fetchPoints, type TelemetryPoint } from "@/features/telemetry/index.ts";

/**
 * B1 `+ Add point` (Investigate.md §B1): search this spacecraft's points (M23, the ⌘K Telemetry
 * search) and add one to plot under the alarm's. Numeric points only; at most 3 added.
 */
const props = defineProps<{
  missionId: MissionId;
  spacecraftId: SpacecraftId;
  /** Already plotted (the alarm's point and the added ones). */
  exclude: readonly string[];
  full: boolean;
}>();
const emit = defineEmits<{ add: [point: TelemetryPoint] }>();
const open = ref(false);
const root = ref<HTMLElement | null>(null);
const q = ref("");
const term = ref("");
let timer: ReturnType<typeof setTimeout> | null = null;
watch(q, (v) => {
  if (timer !== null) clearTimeout(timer);
  timer = setTimeout(() => (term.value = v.trim()), 150);
});
onScopeDispose(() => {
  if (timer !== null) clearTimeout(timer);
});
const results = useRemoteQuery(
  computed(() =>
    open.value ? { m: props.missionId, sc: props.spacecraftId, q: term.value } : null,
  ),
  (k, signal) => fetchPoints(k.m, { q: k.q, spacecraftId: k.sc, limit: 20 }, signal),
);
const shown = computed(() =>
  results.state.value.status === "ready"
    ? results.state.value.value.points
        .filter((p) => p.type === "numeric" && !props.exclude.includes(p.id))
        .slice(0, 8)
    : [],
);
function start() {
  open.value = true;
  void nextTick(() => root.value?.querySelector("input")?.focus());
}
/** Closing removes the field that had focus: it returns to '+ Add point' (a11y A5), not <body>. */
const opener = ref<HTMLElement | null>(null);
function close() {
  open.value = false;
  q.value = "";
  void nextTick(() => opener.value?.querySelector("button")?.focus());
}
function pick(p: TelemetryPoint) {
  emit("add", p);
  close();
}
</script>

<template>
  <span v-if="!open" ref="opener" class="contents"
    ><ApButton size="compact" variant="ghost" :disabled="full" @click="start">{{
      full ? "Plot up to 3 points" : "+ Add point"
    }}</ApButton></span
  >
  <div v-else ref="root" class="flex w-full flex-col gap-2">
    <form class="flex items-end gap-2" @submit.prevent="shown[0] && pick(shown[0])">
      <ApField
        v-model="q"
        class="flex-1"
        label="Add a point"
        type="search"
        mono
        placeholder="Search this spacecraft's points"
        @keydown.esc="close"
      />
      <ApButton size="compact" variant="ghost" @click="close">Cancel</ApButton>
    </form>
    <ApRemote :state="results.state.value" loading-label="SEARCHING…" @retry="results.refetch">
      <ul class="m-0 max-h-56 list-none overflow-auto border border-hairline p-0">
        <li v-for="p in shown" :key="p.id" class="border-t border-hairline-faint first:border-t-0">
          <button
            type="button"
            class="flex min-h-11 w-full cursor-pointer items-center gap-3 px-3 py-1.5 text-left hover:bg-raised"
            @click="pick(p)"
          >
            <span class="flex-none font-mono text-md text-readout">{{ p.name }}</span>
            <span class="min-w-0 flex-1 truncate text-md text-text-3">{{
              p.description ?? p.subsystem ?? ""
            }}</span>
            <span v-if="p.unit" class="flex-none font-mono text-xs text-text-4">{{ p.unit }}</span>
          </button>
        </li>
        <li v-if="shown.length === 0" class="px-3 py-2 text-md text-text-3">
          No numeric points{{ term ? ` match “${term}”` : "" }}.
        </li>
      </ul>
    </ApRemote>
  </div>
</template>
