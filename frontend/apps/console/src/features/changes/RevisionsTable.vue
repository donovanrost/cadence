<script setup lang="ts">
import { AdminModeTag } from "@/shell";
import { ApTable, ApTag, formatAbsolute, plural, type ApColumn } from "@/ui";
import { approvedBy, approverCells, submittedBy, tableActor } from "./revision-record.ts";
import type { RevisionSummary } from "./shapes.ts";

/** Mission configuration revisions, newest first; the live one is marked. */
defineProps<{ rows: readonly RevisionSummary[]; selected: readonly number[] }>();
defineEmits<{ toggle: [revision: number] }>();

const columns: readonly ApColumn[] = [
  { key: "pick", label: "Compare", hiddenLabel: true },
  { key: "revision", label: "Revision", mono: true },
  { key: "applied", label: "Applied", mono: true },
  { key: "by", label: "Submitted by" },
  { key: "approved", label: "Approved by" },
  { key: "why", label: "Why" },
  { key: "changes", label: "Changes", mono: true, align: "end" },
  { key: "kind", label: "Kind" },
];

function kindLabel(row: RevisionSummary): string {
  switch (row.kind) {
    case "baseline":
      return "Baseline";
    case "change_set":
      return "Change set";
    case "rollback":
      return row.rolls_back_to === null ? "Rollback" : `Rollback to r${row.rolls_back_to}`;
    case "legacy_activation":
      // #308: matches rollback_crosses_legacy's words; a kind tag (ca-ux).
      return "Activated outside change sets";
  }
}
</script>

<template>
  <ApTable
    :columns="columns"
    :rows="rows"
    :row-key="(r) => String(r.revision)"
    caption="Configuration revisions"
  >
    <template #cell-pick="{ row }">
      <input
        type="checkbox"
        class="size-4 accent-[var(--color-readout)]"
        :checked="selected.includes(row.revision)"
        :aria-label="`Compare r${row.revision}`"
        @change="$emit('toggle', row.revision)"
      />
    </template>
    <template #cell-revision="{ row }">
      <span class="inline-flex items-center gap-2"
        ><RouterLink
          :to="{ name: 'setup.revision', params: { revision: String(row.revision) } }"
          class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
          >r{{ row.revision }}</RouterLink
        ><ApTag v-if="row.live" state="live" label="Live"
      /></span>
    </template>
    <template #cell-applied="{ row }">{{ formatAbsolute(new Date(row.applied_at)) }}</template>
    <!-- #308/#424: a nameless person reads "Not known" (muted); a service carries the Service tag
      (designers #371, as AuditTable); never "someone" or an id. -->
    <template #cell-by="{ row }">
      <template v-if="tableActor(submittedBy(row))"
        ><span :class="tableActor(submittedBy(row))?.muted ? 'text-text-3' : ''">{{
          tableActor(submittedBy(row))?.text
        }}</span
        ><ApTag v-if="tableActor(submittedBy(row))?.service" class="ml-2" label="Service"
      /></template>
      <template v-else>—</template>
    </template>
    <template #cell-approved="{ row }">
      <template v-if="approvedBy(row).kind === 'not_needed'">Not needed</template>
      <template v-else-if="approverCells(row).length > 0">
        <template v-for="(cell, i) in approverCells(row)" :key="i"
          >{{ i > 0 ? ", " : ""
          }}<span :class="cell.muted ? 'text-text-3' : ''">{{ cell.text }}</span
          ><ApTag v-if="cell.service" class="ml-2" label="Service" /><AdminModeTag
            v-if="cell.adminMode"
            class="ml-1.5 align-middle"
        /></template>
      </template>
      <span v-else class="text-text-3">—</span>
    </template>
    <template #cell-why="{ row }">
      <span
        class="block max-w-[48ch] truncate"
        :class="row.reason ? 'text-text-2' : 'text-text-3'"
        :title="row.reason ?? row.summary ?? undefined"
        >{{ row.reason ?? row.summary ?? "—" }}</span
      >
    </template>
    <template #cell-changes="{ row }">{{ plural(row.entry_count, "change") }}</template>
    <template #cell-kind="{ row }"
      ><span class="text-text-3">{{ kindLabel(row) }}</span></template
    >
  </ApTable>
</template>
