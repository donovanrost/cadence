<script setup lang="ts">
import { ApPanel, plural } from "@/ui";
import { humanize } from "./actions.ts";
import { configKindText } from "./shapes.ts";
import FieldRows from "./FieldRows.vue";
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
            >{{ verb(entry.op) }} {{ configKindText(entry.kind).toLowerCase() }}</span
          >
          {{ " "
          }}<span class="text-readout">{{ entry.entity_name ?? entry.entity_id ?? "new" }}</span>
        </p>
        <FieldRows v-if="entry.fields.length > 0" :fields="entry.fields" />
      </li>
    </ul>
  </ApPanel>
</template>
