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
import { useRouter, type RouteLocationRaw } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import MobileSearchResults from "./MobileSearchResults.vue";
import { MOBILE_GROUPS } from "./mobile.ts";
import { recentItems, rememberOpened } from "./recent.ts";
import { grouped, type Group, type PaletteItem } from "./results.ts";
import { useTabTrap } from "./trapTab.ts";
import { useMobileSearch } from "./useMobileSearch.ts";

/**
 * Phone search (Mobile.md › Search, ux 68d12603): a full-screen sheet over the current tab,
 * opened from the Search tab with the input focused. Cancel or Escape returns to that tab.
 */
const emit = defineEmits<{ close: [] }>();
const router = useRouter();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const input = useTemplateRef<HTMLInputElement>("input");
const query = ref("");
const expanded = shallowRef(new Set<Group>());
const search = useMobileSearch(missionId, query);
let returnFocus: HTMLElement | null = null;

const resolves = (to: RouteLocationRaw) => {
  try {
    return router.resolve(to).matched.length > 0;
  } catch {
    return false;
  }
};
const empty = computed(() => query.value.trim() === "");
const groups = computed(() =>
  grouped(
    empty.value ? recentItems(missionId.value, resolves, "phone") : search.items.value,
    expanded.value,
    MOBILE_GROUPS,
  ),
);

function open(item: PaletteItem) {
  rememberOpened(missionId.value, item, "phone");
  emit("close");
  router.push(item.to).catch((error: unknown) => console.error("Navigation failed", error));
}
function onInput() {
  expanded.value = new Set();
}

onMounted(() => {
  returnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  void nextTick(() => input.value?.focus());
});
onBeforeUnmount(() => returnFocus?.focus());
/** a11y A3 (#243): an aria-modal div, so Tab is kept inside it by hand (a native <dialog> isn't). */
const root = useTemplateRef<HTMLElement>("root");
useTabTrap(root, () => emit("close"));
</script>

<template>
  <div
    ref="root"
    role="dialog"
    aria-modal="true"
    aria-label="Search"
    class="fixed inset-0 z-50 flex flex-col bg-panel"
  >
    <div class="flex flex-none items-center gap-2 border-b border-hairline bg-chrome pl-4">
      <label for="phone-search" class="sr-only">Search</label>
      <input
        id="phone-search"
        ref="input"
        v-model="query"
        type="search"
        enterkeyhint="search"
        autocomplete="off"
        placeholder="Spacecraft, alarms, requests"
        class="h-14 min-w-0 flex-1 bg-transparent text-lg text-readout outline-none placeholder:text-text-4"
        @input="onInput"
      />
      <span v-if="search.pending.value && !empty" class="font-mono text-xs text-text-4 uppercase"
        >Searching…</span
      >
      <button
        type="button"
        class="min-h-12 cursor-pointer border-0 bg-transparent px-4 text-md text-readout"
        @click="emit('close')"
      >
        Cancel
      </button>
    </div>
    <MobileSearchResults
      :groups="groups"
      :query="query.trim()"
      :sources="empty ? {} : search.sources.value"
      :alarms-truncated="!empty && search.alarmsTruncated.value"
      @open="open"
      :expanded="expanded"
      @expand="(g) => (expanded = new Set([...expanded, g]))"
      @collapse="(g) => (expanded = new Set([...expanded].filter((x) => x !== g)))"
      @retry="(g) => search.retry[g]?.()"
    />
  </div>
</template>
