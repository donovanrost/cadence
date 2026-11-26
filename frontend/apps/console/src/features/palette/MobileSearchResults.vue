<script setup lang="ts">
import { computed, nextTick, ref, useId, useTemplateRef, watch } from "vue";
import { ApButton, ApStatusMark } from "@/ui";
import { PER_GROUP, type Group, type GroupView, type PaletteItem } from "./results.ts";
import type { SourceState } from "./useMobileSearch.ts";

/** The phone sheet's groups: rows ≥ 56px (mark, title, one subtitle), `Show all N`, a failed group's Try again. */
const props = defineProps<{
  groups: readonly GroupView[];
  query: string;
  sources: Readonly<Partial<Record<Group, SourceState>>>;
  /** Groups showing all their rows (Show all N), so the toggle can offer Show first N. */
  expanded: ReadonlySet<Group>;
  /** More alarms match than were read (#827): the list must not look complete. */
  alarmsTruncated?: boolean;
}>();
const emit = defineEmits<{
  open: [item: PaletteItem];
  expand: [group: Group];
  collapse: [group: Group];
  retry: [group: Group];
}>();
const failed = computed(() =>
  (["Alarms", "Requests", "Spacecraft"] as const).filter((g) => props.sources[g] === "failed"),
);
const total = computed(() => props.groups.reduce((n, g) => n + g.items.length + g.more, 0));

/** a11y B3 (#243, ux #458): Show all N is a toggle that stays (Show first N), so focus stays on it. */
const listId = useId();
const toggle = (g: Group) => (props.expanded.has(g) ? emit("collapse", g) : emit("expand", g));

/**
 * a11y A5 (#243, ux #458): Try again's row goes while its group reloads. Once the group is back,
 * focus goes to its heading; if it failed again, to its Try again. Only if focus fell to <body>
 * meanwhile: someone who moved on keeps their place (B4).
 */
const root = useTemplateRef<HTMLElement>("root");
const retrying = ref<Group | null>(null);
function retry(g: Group) {
  retrying.value = g;
  emit("retry", g);
}
watch(
  () => [props.groups, props.sources] as const,
  async () => {
    const g = retrying.value;
    if (g === null || props.sources[g] === "loading") return;
    // Settled one way or another: never pull focus later (ux, dashboards #492).
    retrying.value = null;
    const back = props.groups.some((v) => v.group === g);
    const failedAgain = props.sources[g] === "failed";
    await nextTick();
    if (document.activeElement !== document.body) return;
    const el = root.value;
    // Back with rows → its heading; failed again → its Try again; back empty → the first heading,
    // else the search field (ux #492).
    const target = back
      ? el?.querySelector<HTMLElement>(`[data-heading="${g}"]`)
      : failedAgain
        ? el?.querySelector<HTMLElement>(`[data-retry="${g}"]`)
        : (el?.querySelector<HTMLElement>("[data-heading]") ??
          el?.closest('[role="dialog"]')?.querySelector<HTMLElement>('input[type="search"]'));
    target?.focus();
  },
);
</script>

<template>
  <div ref="root" class="min-h-0 flex-1 overflow-auto pb-[env(safe-area-inset-bottom)]">
    <p class="sr-only" aria-live="polite">
      {{ query ? (total === 1 ? "1 result" : `${total} results`) : "" }}
    </p>
    <p v-if="!query && groups.length === 0" class="m-0 px-4 py-6 text-md text-text-3">
      Search spacecraft by name or number, alarms by point, requests by title.
    </p>
    <p
      v-else-if="query && groups.length === 0 && failed.length === 0"
      class="m-0 px-4 py-6 text-md text-text-3"
    >
      Nothing matches "{{ query }}".
    </p>
    <div
      v-for="g in failed"
      :key="`failed-${g}`"
      class="flex min-h-14 items-center gap-3 border-b border-hairline px-4"
    >
      <span class="flex-1 text-md text-text-2">{{ g }} couldn't load.</span>
      <!-- B7 (ux #492): named with its group. -->
      <ApButton
        variant="ghost"
        size="compact"
        :data-retry="g"
        :aria-label="`Try again, ${g}`"
        @click="retry(g)"
        >Try again</ApButton
      >
    </div>
    <p v-if="alarmsTruncated" class="m-0 px-4 py-3 text-md text-text-3" role="status">
      More alarms match than are shown. Add a spacecraft or point to narrow the search.
    </p>
    <section v-for="g in groups" :key="g.group" :aria-label="g.group">
      <h2 :data-heading="g.group" tabindex="-1" class="ap-label m-0 px-4 pt-3 pb-1">
        {{ g.group }}
      </h2>
      <ul :id="`${listId}-${g.group}`" class="m-0 list-none p-0">
        <li v-for="item in g.items" :key="item.key">
          <button
            type="button"
            class="flex min-h-14 w-full cursor-pointer items-center gap-3 border-0 border-b border-hairline bg-transparent px-4 py-2 text-left hover:bg-raised"
            @click="emit('open', item)"
          >
            <ApStatusMark :state="item.state ?? 'neutral'" />
            <span class="flex min-w-0 flex-1 flex-col">
              <span class="truncate font-mono text-base text-readout">{{ item.title }}</span>
              <span class="truncate text-md text-text-3">{{ item.subtitle }}</span>
            </span>
          </button>
        </li>
      </ul>
      <button
        v-if="g.more > 0 || expanded.has(g.group)"
        type="button"
        class="min-h-12 w-full cursor-pointer border-0 bg-transparent px-4 text-left font-mono text-xs text-text-3 uppercase"
        :aria-expanded="expanded.has(g.group)"
        :aria-controls="`${listId}-${g.group}`"
        :aria-label="`${expanded.has(g.group) ? `Show first ${PER_GROUP}` : `Show all ${g.items.length + g.more}`}, ${g.group}`"
        @click="toggle(g.group)"
      >
        {{
          expanded.has(g.group) ? `Show first ${PER_GROUP}` : `Show all ${g.items.length + g.more}`
        }}
      </button>
    </section>
  </div>
</template>
