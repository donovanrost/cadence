<script setup lang="ts">
import { ApPanel, plural } from "@/ui";
import { humanize } from "./itemLines.ts";
import { configKindText, type EntryOp } from "./shapes.ts";
import { isKnown, type Unrecognized } from "@/api";
import FieldRows from "./FieldRows.vue";
import type { RevisionEntry } from "./shapes.ts";

/** What a revision changed: per entity, `path  − before  + after` rows (Changes.md §4). */
defineProps<{ entries: readonly RevisionEntry[] }>();
const verbs: Readonly<Record<EntryOp, string>> = {
  create: "Added",
  update: "Changed",
  delete: "Removed",
  archive: "Archived",
};
const verb = (op: EntryOp | Unrecognized) => (isKnown(op) ? verbs[op] : humanize(op.unrecognized));
const opText = (op: EntryOp | Unrecognized) => (isKnown(op) ? op : op.unrecognized);
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
          :title="`${opText(entry.op)} ${entry.kind} ${entry.entity_id ?? ''}`"
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
