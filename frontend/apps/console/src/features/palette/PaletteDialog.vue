<script setup lang="ts">
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  shallowRef,
  useTemplateRef,
} from "vue";
import { useRoute, useRouter, type RouteLocationRaw } from "vue-router";
import { isParamlessRouteName, useConsoleScope } from "@/shell/index.ts";
import { ApKbd } from "@/ui";
import { useCommandAccess } from "@/features/commands/index.ts";
import { useFleet } from "@/features/fleet/index.ts";
import PaletteResults from "./PaletteResults.vue";
import { recentItems, rememberOpened } from "./recent.ts";
import {
  grouped,
  groupJump,
  SETUP_GROUPS,
  rowsOf,
  search,
  type Group,
  type PageEntry,
  type PaletteItem,
} from "./results.ts";
import { usePointSearch } from "./usePointSearch.ts";
import { useSourceSearch } from "./useSourceSearch.ts";

/** The modal query line: combobox input + grouped listbox. Esc closes and restores focus. */
const emit = defineEmits<{ close: [] }>();
const router = useRouter();
const route = useRoute();
const scope = useConsoleScope();
const missionId = computed(() => (scope.value.kind === "mission" ? scope.value.mission.id : null));
const fleet = useFleet(missionId, { live: false });
const access = useCommandAccess();

const input = useTemplateRef<HTMLInputElement>("input");
const query = ref("");
const active = ref(0);
const expanded = shallowRef(new Set<Group>());
let returnFocus: HTMLElement | null = null;

const pages = computed<PageEntry[]>(() =>
  router
    .getRoutes()
    .flatMap((r) =>
      isParamlessRouteName(r.name) &&
      r.meta.title &&
      r.meta.mode &&
      !/:(?!org\b|mission\b)/.test(r.path) &&
      (access.value.request || r.name !== "ops.commands.new")
        ? [{ name: r.name, title: r.meta.title, mode: r.meta.mode }]
        : [],
    ),
);
const spacecraft = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);
const points = usePointSearch(missionId, query, spacecraft);
const sources = useSourceSearch(
  missionId,
  query,
  computed(() => access.value.request),
);
/** Recent first on an empty query (Palette.md); routes that no longer resolve are dropped. */
const resolves = (to: RouteLocationRaw) => {
  try {
    return router.resolve(to).matched.length > 0;
  } catch {
    return false;
  }
};
const recent = computed(() =>
  missionId.value && query.value.trim() === "" ? recentItems(missionId.value, resolves) : [],
);
const groups = computed(() =>
  grouped(
    [
      ...recent.value,
      ...search(query.value, spacecraft.value, pages.value, access.value.request),
      ...points.items.value,
      ...sources.items.value,
    ],
    expanded.value,
    route.meta.mode === "setup" ? SETUP_GROUPS : undefined,
  ),
);
const rows = computed(() => rowsOf(groups.value));
const strip = computed(() => {
  const s = scope.value;
  if (s.kind !== "mission") return "";
  // Real counts only; an unknown count is left out (Palette.md strip).
  const sc = fleet.state.value.status === "ready" ? fleet.state.value.value.counts.total : null;
  const stations = sources.stationCount.value;
  return [
    s.mission.name,
    // The previous results stay while a search is out (Palette.md: no flicker).
    points.pending.value || sources.pending.value ? "Searching…" : null,
    sc === null ? null : `${sc} SC`,
    stations === null ? null : `${stations} ${stations === 1 ? "station" : "stations"}`,
  ]
    .filter((p): p is string => p !== null)
    .join(" · ");
});

function go(item: PaletteItem, command = false) {
  const to = command ? item.commandTo : item.to;
  if (to === null) return;
  if (missionId.value) rememberOpened(missionId.value, item);
  emit("close");
  router.push(to).catch((error: unknown) => console.error("Navigation failed", error));
}
function onKey(event: KeyboardEvent) {
  const count = rows.value.length;
  if (event.key === "Escape") return emit("close");
  // Focus trap (qa #13): the input is the dialog's only tab stop; Tab moves between groups.
  if (event.key === "Tab") {
    event.preventDefault();
    if (count) active.value = groupJump(rows.value, active.value, event.shiftKey);
    return;
  }
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    if (count) active.value = (active.value + (event.key === "ArrowDown" ? 1 : count - 1)) % count;
    return;
  }
  if (event.key === "Enter") {
    event.preventDefault();
    const row = rows.value[active.value];
    if (row?.kind === "more") expand(row.group);
    else if (row) go(row.item, event.metaKey || event.ctrlKey);
  }
}
function onInput() {
  active.value = 0;
  expanded.value = new Set();
}
function expand(group: Group) {
  expanded.value = new Set([...expanded.value, group]);
}

onMounted(() => {
  returnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  void nextTick(() => input.value?.focus());
});
onBeforeUnmount(() => returnFocus?.focus());
</script>

<template>
  <div class="fixed inset-0 z-50 bg-[rgba(3,5,8,0.7)]" @click.self="emit('close')">
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Search and run commands"
      class="mx-auto mt-[14vh] flex max-h-[70vh] w-[min(680px,calc(100vw-32px))] flex-col border border-line bg-panel max-md:mt-0 max-md:h-dvh max-md:max-h-none max-md:w-full max-md:border-0"
    >
      <p
        class="m-0 flex justify-between border-b border-hairline px-4 py-2 font-mono text-xs text-text-4 uppercase"
      >
        <span>Cadence // query</span><span>{{ strip }}</span>
      </p>
      <div class="flex items-center gap-3 border-b border-hairline px-4">
        <span aria-hidden="true" class="font-mono text-text-4">›</span>
        <label for="palette-input" class="sr-only">Search</label>
        <input
          id="palette-input"
          ref="input"
          v-model="query"
          role="combobox"
          aria-expanded="true"
          aria-controls="palette-results"
          aria-autocomplete="list"
          :aria-activedescendant="rows[active] ? `palette-${rows[active]?.key}` : undefined"
          autocomplete="off"
          :placeholder="
            access.request
              ? 'Spacecraft, telemetry, commands, stations…  (# > @)'
              : 'Spacecraft, telemetry, stations…  (# @)'
          "
          class="h-14 min-w-0 flex-1 bg-transparent text-lg text-readout outline-none placeholder:text-text-4"
          @input="onInput"
          @keydown="onKey"
        />
        <ApKbd class="max-md:hidden">Esc</ApKbd>
      </div>
      <PaletteResults
        :groups="groups"
        :active-key="rows[active]?.key ?? null"
        :can-command="access.request"
        @open="go"
        @expand="expand"
      />
      <p
        class="m-0 flex flex-wrap gap-4 border-t border-hairline px-4 py-2 font-mono text-xs text-text-4 uppercase max-md:hidden"
      >
        <span>↑↓ move</span><span>↵ open</span><span v-if="access.request">⌘↵ command it</span
        ><span>G N now</span><span>G C contacts</span><span>[ ] prev/next sc</span>
      </p>
    </div>
  </div>
</template>
