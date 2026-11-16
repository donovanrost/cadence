<script setup lang="ts">
import { computed } from "vue";
import { ApCheckRows, plural, type ApCheckRow } from "@/ui";
import { groupedLines, type Preview } from "./actions.ts";
import AlarmLinks from "./AlarmLinks.vue";
import AppInstallLinks from "./AppInstallLinks.vue";
import DependentLinks from "./DependentLinks.vue";
import { dependents } from "./dependents.ts";
import { alarmPoints, appHolds, checkTitle, modelHolds } from "./holds.ts";
import ModelApprovalLinks from "./ModelApprovalLinks.vue";
import { checkKeyText, checkLabel } from "./preview.ts";

/**
 * K2's rows, links and technical details for one run of the checks. `dimmed` while they're the
 * previous run's (ux B4): one instance serves both, so a focused link that survives keeps focus.
 * `leftBy` names what the conflict's base came from ("r8"), for the conflict sentence.
 */
const props = defineProps<{ preview: Preview; dimmed: boolean; leftBy?: string | undefined }>();

const rows = computed((): readonly ApCheckRow[] =>
  props.preview.checks.map((check) => ({
    key: checkKeyText(check.key),
    label: checkTitle(check.items) ?? checkLabel(check.key),
    sentence:
      check.items.length === 0
        ? check.key === "conflicts"
          ? "Every change applies cleanly on the live revision"
          : check.key === "compatibility"
            ? "Profile framing matches every transport's ingress"
            : "Every change is valid"
        : plural(groupedLines(check.items).length, "problem"),
    detail: groupedLines(check.items, props.leftBy).slice(0, 5).join(" · "),
    ...(check.verdict === "go"
      ? { state: "nominal" as const, verdict: "GO" }
      : check.verdict === "hold"
        ? { state: "caution" as const, verdict: "HOLD" }
        : { state: "crit" as const, verdict: "NO-GO" }),
  })),
);
/** Raw comparisons behind the plain sentences (ux: machine detail goes to Technical details). */
const technical = computed(() =>
  props.preview.checks.flatMap((c) => c.items.flatMap((i) => (i.detail ? [i.detail] : []))),
);
</script>

<template>
  <ApCheckRows :rows="rows" :dimmed="dimmed" />
  <DependentLinks :points="dependents(preview)" />
  <AlarmLinks :points="alarmPoints(preview)" />
  <AppInstallLinks :holds="appHolds(preview)" />
  <ModelApprovalLinks :holds="modelHolds(preview)" />
  <details v-if="technical.length > 0" class="border-t border-hairline px-4 py-2.5">
    <summary class="ap-label cursor-pointer">Technical details</summary>
    <ul class="m-0 mt-2 flex list-none flex-col gap-1 p-0 font-mono text-xs text-text-3">
      <li v-for="(t, i) in technical" :key="i">{{ t }}</li>
    </ul>
  </details>
</template>
