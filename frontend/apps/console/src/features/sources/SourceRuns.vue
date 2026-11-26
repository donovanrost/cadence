<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, useId } from "vue";
import { ApButton, ApEmptyState, ApPanel, ApTable, ApTag, formatShort, type ApColumn } from "@/ui";
import { ACTION_LINES, runKindText, runTag, sourceFailure } from "./present.ts";
import { runAction, type SourceRun } from "./writes.ts";

/** S3 · TSDB jobs, newest 20. A failed run offers Retry, a stuck one Requeue (W7). */
const props = defineProps<{
  missionId: MissionId;
  runs: readonly SourceRun[];
  editable: boolean;
}>();
const emit = defineEmits<{ done: [note: { tone: "nominal" | "crit"; text: string }] }>();
const columns = computed<readonly ApColumn[]>(() => [
  { key: "kind", label: "Job" },
  { key: "status", label: "Status" },
  { key: "at", label: "Started", mono: true },
  { key: "error", label: "Error" },
  ...(props.editable ? [{ key: "act", label: "Action", hiddenLabel: true }] : []),
]);
const busy = ref<string | null>(null);
/**
 * #244 (A6/B7): the Retry/Requeue explanation was only a hover title. Each action present says
 * once, visibly, under the table, and its buttons point at that line.
 */
const lineId = { retry: useId(), requeue: useId() } as const;
/**
 * B7 (ux on #569): describedby isn't a name. Each button names its row, label first: "Retry,
 * Reconcile run, 11-19 03:10Z". While busy the kit's own reason describes it, so the line's id is
 * passed only when it's enabled (a fallthrough attribute would override the kit's).
 */
const actionName = (r: SourceRun) =>
  `${action(r) === "requeue" ? "Requeue" : "Retry"}, ${runKindText(r)} run, ${formatShort(new Date(r.started_at))}`;
const shownActions = computed(() =>
  (["retry", "requeue"] as const).filter((a) => props.runs.some((r) => action(r) === a)),
);
const action = (r: SourceRun) =>
  r.actions?.find((a): a is "retry" | "requeue" => a === "retry" || a === "requeue") ?? null;
async function act(r: SourceRun) {
  const a = action(r);
  if (!a || busy.value) return;
  busy.value = r.job_id;
  try {
    const res = await runAction(props.missionId, r.job_id, a);
    emit(
      "done",
      res.ok
        ? { tone: "nominal", text: a === "retry" ? "Retried." : "Requeued." }
        : { tone: "crit", text: sourceFailure(res.error) },
    );
  } finally {
    busy.value = null;
  }
}
</script>

<template>
  <ApPanel index="S3" title="Runs" flush>
    <ApEmptyState
      v-if="runs.length === 0"
      state="off"
      headline="No runs"
      sentence="Provision, reconcile and deprovision jobs show here."
    />
    <ApTable v-else :columns="columns" :rows="runs" :row-key="(r) => r.job_id" caption="Runs">
      <template #cell-kind="{ row }">{{ runKindText(row) }}</template>
      <template #cell-status="{ row }"
        ><ApTag :state="runTag(row).state" :label="runTag(row).label"
      /></template>
      <template #cell-at="{ row }">{{ formatShort(new Date(row.started_at)) }}</template>
      <template #cell-error="{ row }"
        ><span class="text-text-2">{{ row.error?.message ?? "—" }}</span></template
      >
      <template #cell-act="{ row }">
        <ApButton
          v-if="action(row)"
          size="compact"
          variant="ghost"
          :title="ACTION_LINES[action(row) ?? 'retry']"
          :aria-label="actionName(row)"
          :aria-describedby="busy === null ? lineId[action(row) ?? 'retry'] : undefined"
          :disabled="busy !== null"
          disabled-reason="Working…"
          @click="act(row)"
          >{{ action(row) === "retry" ? "Retry" : "Requeue" }}</ApButton
        >
      </template>
    </ApTable>
    <div v-if="editable && shownActions.length > 0" class="flex flex-col gap-0.5 px-4 py-3">
      <p v-for="a in shownActions" :id="lineId[a]" :key="a" class="m-0 text-sm text-text-3">
        {{ ACTION_LINES[a] }}
      </p>
    </div>
  </ApPanel>
</template>
