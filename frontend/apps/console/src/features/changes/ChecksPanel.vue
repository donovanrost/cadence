<script setup lang="ts">
import { computed } from "vue";
import type { RemoteState } from "@/api";
import { ApButton, ApCallout, ApCheckRows, ApPanel, ApRemote, plural, type ApCheckRow } from "@/ui";
import { itemLine, type Preview } from "./actions.ts";

/** K2 Checks: the server's dry run of the staged set (validation, conflicts; more kinds in P2). */
const props = defineProps<{ preview: RemoteState<Preview> }>();
defineEmits<{ retry: [] }>();

const labels: Readonly<Record<string, string>> = {
  validation: "Validation",
  conflicts: "Conflicts",
};

function rows(preview: Preview): readonly ApCheckRow[] {
  return preview.checks.map((check) => ({
    key: check.key,
    label: labels[check.key] ?? check.key,
    sentence:
      check.items.length === 0
        ? check.key === "conflicts"
          ? "Every change applies cleanly on the live revision"
          : check.key === "compatibility"
            ? "Profile framing matches every transport's ingress"
            : "Every change is valid"
        : `${plural(check.items.length, "problem")}`,
    detail: check.items.map(itemLine).slice(0, 5).join(" · "),
    ...(check.verdict === "go"
      ? { state: "nominal" as const, verdict: "GO" }
      : check.verdict === "hold"
        ? { state: "caution" as const, verdict: "HOLD" }
        : { state: "crit" as const, verdict: "NO-GO" }),
  }));
}
const meta = computed(() =>
  props.preview.status === "ready"
    ? `Verdict ${props.preview.value.verdict.replace("_", "-")}`
    : undefined,
);
</script>

<template>
  <ApPanel index="K2" title="Checks" :meta="meta" flush>
    <ApCallout v-if="preview.status === 'failed'" tone="caution">
      Checks couldn't run. This change set may have been applied or discarded by someone else.
      <template #action
        ><ApButton size="compact" @click="$emit('retry')">Reload</ApButton></template
      >
    </ApCallout>
    <ApRemote v-else :state="preview" loading-label="Running checks…" @retry="$emit('retry')">
      <template #default="{ value }"><ApCheckRows :rows="rows(value)" /></template>
    </ApRemote>
  </ApPanel>
</template>
