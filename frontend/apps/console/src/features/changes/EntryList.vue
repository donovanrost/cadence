<script setup lang="ts">
import { ApPanel, plural } from "@/ui";
import { humanize } from "./actions.ts";
import { showValue } from "./api.ts";
import type { RevisionEntry } from "./shapes.ts";

/** What a revision changed: per entity, `path  − before  + after` rows (Changes.md §4). */
defineProps<{ entries: readonly RevisionEntry[] }>();
const verbs: Readonly<Record<string, string>> = {
  create: "Added",
  update: "Changed",
  delete: "Removed",
  archive: "Archived",
};
const verb = (op: string) => verbs[op] ?? humanize(op);
</script>

<template>
  <ApPanel index="V2" title="Changes" :meta="plural(entries.length, 'entry', 'entries')" flush>
    <ul class="m-0 list-none p-0">
      <li
        v-for="(entry, i) in entries"
        :key="`${entry.kind}-${entry.entity_id ?? i}`"
        class="border-t border-hairline px-4 py-3 first:border-t-0"
      >
        <p
          class="m-0 text-sm text-text-2"
          :title="`${entry.op} ${entry.kind} ${entry.entity_id ?? ''}`"
        >
          <span class="text-text-3"
            >{{ verb(entry.op) }} {{ humanize(entry.kind).toLowerCase() }}</span
          >
          {{ " "
          }}<span class="text-readout">{{ entry.entity_name ?? entry.entity_id ?? "new" }}</span>
        </p>
        <ul
          v-if="entry.fields.length > 0"
          class="m-0 mt-1.5 flex list-none flex-col gap-0.5 p-0 text-sm"
        >
          <li
            v-for="f in entry.fields"
            :key="f.path"
            class="grid grid-cols-[minmax(0,240px)_1fr] gap-3"
          >
            <span class="truncate text-text-3" :title="f.path">{{ f.label ?? f.path }}</span>
            <span
              class="truncate font-mono"
              :title="`${showValue(f.before, f.unit, f.format)} → ${showValue(f.after, f.unit, f.format)}`"
              ><span class="text-text-3">{{ showValue(f.before, f.unit, f.format) }}</span> →
              <span class="text-readout">{{ showValue(f.after, f.unit, f.format) }}</span></span
            >
          </li>
        </ul>
      </li>
    </ul>
  </ApPanel>
</template>
