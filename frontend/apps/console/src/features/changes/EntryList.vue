<script setup lang="ts">
import { ApPanel, plural } from "@/ui";
import { showValue } from "./api.ts";
import type { RevisionEntry } from "./shapes.ts";

/** What a revision changed: per entity, `path  − before  + after` rows (Changes.md §4). */
defineProps<{ entries: readonly RevisionEntry[] }>();
</script>

<template>
  <ApPanel index="V2" title="Changes" :meta="plural(entries.length, 'entry', 'entries')" flush>
    <ul class="m-0 list-none p-0">
      <li
        v-for="(entry, i) in entries"
        :key="`${entry.kind}-${entry.entity_id ?? i}`"
        class="border-t border-hairline px-4 py-3 first:border-t-0"
      >
        <p class="m-0 font-mono text-sm text-text-2">
          <span class="text-text-4">{{ entry.op }} {{ entry.kind }}</span>
          {{ entry.entity_id ?? "new" }}
        </p>
        <ul
          v-if="entry.fields.length > 0"
          class="m-0 mt-1.5 flex list-none flex-col gap-0.5 p-0 font-mono text-sm"
        >
          <li
            v-for="f in entry.fields"
            :key="f.path"
            class="grid grid-cols-[minmax(0,240px)_1fr_1fr] gap-3"
          >
            <span class="truncate text-text-3" :title="f.path">{{ f.path }}</span>
            <span class="truncate text-crit-text" :title="showValue(f.before)"
              >− {{ showValue(f.before) }}</span
            >
            <span class="truncate text-nominal-text" :title="showValue(f.after)"
              >+ {{ showValue(f.after) }}</span
            >
          </li>
        </ul>
      </li>
    </ul>
  </ApPanel>
</template>
