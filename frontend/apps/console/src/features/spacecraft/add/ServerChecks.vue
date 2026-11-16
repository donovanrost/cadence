<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import {
  checkKeyText,
  checkLabel,
  itemLine,
  previewOps,
  type Preview,
} from "@/features/changes/index.ts";
import { useMissionScope } from "@/shell";
import { ApCheckRows, ApPanel, ApRemote, plural, type ApCheckRow } from "@/ui";
import { useDraft } from "./context.ts";
import { batchOps } from "./stage.ts";

/** Server dry run of the batch (POST config/preview {ops}): validation and conflicts, nothing written. */
const { proposal, profiles } = useDraft();
const scope = useMissionScope();
const ops = computed(() => {
  const p = proposal();
  if (p.status !== "ready") return null;
  const batch = batchOps(p.report.rows, profiles(), p.profileId);
  return batch.ok ? batch.ops : null;
});
const key = computed(() =>
  ops.value ? { missionId: scope.value.mission.id, ops: ops.value } : null,
);
const preview = useRemoteQuery(key, previewOps);

function rows(p: Preview): readonly ApCheckRow[] {
  return p.checks.map((check) => ({
    key: checkKeyText(check.key),
    label: checkLabel(check.key),
    sentence:
      check.items.length === 0
        ? check.key === "conflicts"
          ? "Nothing clashes with the live configuration"
          : "Every spacecraft is valid"
        : plural(check.items.length, "problem"),
    detail: check.items
      .flatMap((i) => [itemLine(i)])
      .slice(0, 4)
      .join(" · "),
    ...(check.verdict === "go"
      ? { state: "nominal" as const, verdict: "Pass" }
      : check.verdict === "hold"
        ? { state: "caution" as const, verdict: "Hold" }
        : { state: "crit" as const, verdict: "NO-GO" }),
  }));
}
</script>

<template>
  <ApPanel v-if="key" index="A5" title="Server checks" meta="Dry run · nothing written" flush>
    <ApRemote
      :state="preview.state.value"
      loading-label="Checking with the server…"
      @retry="preview.refetch"
    >
      <template #default="{ value }"><ApCheckRows :rows="rows(value)" /></template>
    </ApRemote>
  </ApPanel>
</template>
