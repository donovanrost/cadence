<script setup lang="ts">
import { computed } from "vue";
import type { RouteLocationRaw } from "vue-router";
import { ApStatusMark } from "@/ui";
import type { Group, GroupView } from "./results.ts";

/** Grouped listbox. Rows are options; the active row is tracked by the input's activedescendant. */
const props = defineProps<{ groups: readonly GroupView[]; activeKey: string | null }>();
const total = computed(() => props.groups.reduce((n, g) => n + g.items.length + g.more, 0));
const emit = defineEmits<{ open: [to: RouteLocationRaw]; expand: [group: Group] }>();
</script>

<template>
  <p class="sr-only" aria-live="polite">{{ total === 1 ? "1 result" : `${total} results` }}</p>
  <div
    id="palette-results"
    role="listbox"
    aria-label="Results"
    class="min-h-0 flex-1 overflow-auto py-1"
  >
    <p v-if="groups.length === 0" class="m-0 px-4 py-6 text-md text-text-3">
      <span class="block font-semibold text-readout">No matches</span>
      Try a spacecraft name or SCID like 312, or a page like Contacts.
    </p>
    <div v-for="g in groups" :key="g.group" role="group" :aria-label="g.group">
      <p class="ap-label m-0 flex items-center gap-3 px-4 pt-3 pb-1">
        {{ g.group }}<span aria-hidden="true" class="h-px flex-1 bg-hairline" />
      </p>
      <div
        v-for="item in g.items"
        :id="`palette-${item.key}`"
        :key="item.key"
        role="option"
        :aria-selected="item.key === activeKey"
        class="flex cursor-pointer items-center gap-3 px-4 py-2"
        :class="
          item.key === activeKey
            ? 'bg-raised-hi shadow-[inset_2px_0_0_var(--color-readout)]'
            : 'hover:bg-raised'
        "
        @click="emit('open', item.to)"
      >
        <span class="flex size-7 flex-none items-center justify-center border border-line">
          <ApStatusMark :state="item.state ?? 'neutral'" />
        </span>
        <span class="flex min-w-0 flex-1 flex-col">
          <span class="truncate font-mono text-base text-readout">{{ item.title }}</span>
          <span class="truncate text-md text-text-3">{{ item.subtitle }}</span>
        </span>
        <span class="font-mono text-xs text-text-4 uppercase">{{ item.hint }}</span>
      </div>
      <button
        v-if="g.more > 0"
        type="button"
        class="w-full cursor-pointer px-4 py-2 text-left font-mono text-xs text-text-3 uppercase hover:text-readout"
        @click="emit('expand', g.group)"
      >
        Show all {{ g.items.length + g.more }} {{ g.group.toLowerCase() }}
      </button>
    </div>
  </div>
</template>
