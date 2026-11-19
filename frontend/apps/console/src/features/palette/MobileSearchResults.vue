<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApStatusMark } from "@/ui";
import type { Group, GroupView, PaletteItem } from "./results.ts";
import type { SourceState } from "./useMobileSearch.ts";

/** The phone sheet's groups: rows ≥ 56px (mark, title, one subtitle), `Show all N`, a failed group's Try again. */
const props = defineProps<{
  groups: readonly GroupView[];
  query: string;
  sources: Readonly<Partial<Record<Group, SourceState>>>;
}>();
const emit = defineEmits<{
  open: [item: PaletteItem];
  expand: [group: Group];
  retry: [group: Group];
}>();
const failed = computed(() =>
  (["Alarms", "Requests", "Spacecraft"] as const).filter((g) => props.sources[g] === "failed"),
);
const total = computed(() => props.groups.reduce((n, g) => n + g.items.length + g.more, 0));
</script>

<template>
  <div class="min-h-0 flex-1 overflow-auto pb-[env(safe-area-inset-bottom)]">
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
      <ApButton variant="ghost" size="compact" @click="emit('retry', g)">Try again</ApButton>
    </div>
    <section v-for="g in groups" :key="g.group" :aria-label="g.group">
      <h2 class="ap-label m-0 px-4 pt-3 pb-1">{{ g.group }}</h2>
      <ul class="m-0 list-none p-0">
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
        v-if="g.more > 0"
        type="button"
        class="min-h-12 w-full cursor-pointer border-0 bg-transparent px-4 text-left font-mono text-xs text-text-3 uppercase"
        @click="emit('expand', g.group)"
      >
        Show all {{ g.items.length + g.more }}
      </button>
    </section>
  </div>
</template>
