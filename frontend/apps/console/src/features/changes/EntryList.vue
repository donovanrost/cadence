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
</script>

<template>
  <ApPanel index="V2" title="Changes" :meta="plural(entries.length, 'change')" flush>
    <ul class="m-0 list-none p-0">
      <li
        v-for="(entry, i) in entries"
        :key="`${entry.kind}-${entry.entity_id ?? i}`"
        class="border-t border-hairline px-4 py-3 first:border-t-0"
      >
        <!-- #308 (U25): the entity's name, or nothing ("Changed profile"); never its id or raw op. -->
        <p class="m-0 text-sm text-text-2">
          <span class="text-text-3"
            >{{ verb(entry.op) }} {{ configKindText(entry.kind).toLowerCase() }}</span
          >
          {{ " "
          }}<span v-if="entry.entity_name" class="text-readout">{{ entry.entity_name }}</span>
        </p>
        <FieldRows v-if="entry.fields.length > 0" :fields="entry.fields" />
      </li>
    </ul>
  </ApPanel>
</template>
