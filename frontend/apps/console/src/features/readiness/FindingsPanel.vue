<script setup lang="ts">
import { computed } from "vue";
import { formatCount, plural, ApButton, ApCallout, ApListRow, ApPanel } from "@/ui";
import type { Readiness } from "./api.ts";
import { fixLink, orderedFindings, severityState, severityWord } from "./present.ts";

/**
 * R1: one line per cause (grouped server-side), blockers first, each with at most one fix. Each
 * title leads with its severity word, so the mark isn't the only signal (a11y B2).
 */
const props = defineProps<{ readiness: Readiness }>();

const findings = computed(() => orderedFindings(props.readiness));
const blockers = computed(() => props.readiness.verdict.blocker);
const meta = computed(() => {
  const items = findings.value.reduce((sum, f) => sum + f.affectedCount, 0);
  const lines = plural(findings.value.length, "line");
  // "3,006 items → 4 lines" only when grouping actually collapsed something.
  return items > findings.value.length
    ? `Grouped by cause · ${formatCount(items)} items → ${lines}`
    : `Grouped by cause · ${lines}`;
});
const others = computed(() => findings.value.filter((f) => f.severity !== "blocker").length);
</script>

<template>
  <ApPanel index="R1" title="Findings" :meta="meta" flush>
    <ApCallout v-if="blockers === 0" tone="nominal">
      No blockers. Nothing stops commanding or contacts.<template v-if="others === 0">
        No suggestions either.</template
      >
    </ApCallout>
    <ApCallout v-else tone="crit">
      {{ plural(blockers, "blocker") }} {{ blockers === 1 ? "stops" : "stop" }} commanding or
      contacts.
    </ApCallout>
    <ul v-if="findings.length > 0" class="m-0 list-none border-t border-hairline p-0">
      <ApListRow
        v-for="finding in findings"
        :key="finding.id"
        :state="severityState(finding.severity)"
        :sentence="finding.body"
      >
        <template #title>
          <span :class="finding.severity === 'optional' ? 'text-text-2' : ''"
            >{{ severityWord(finding.severity) }} · {{ finding.title }}</span
          >
        </template>
        <template v-if="finding.fix" #action>
          <ApButton size="compact" :to="fixLink(finding.fix, finding.severity).to">{{
            fixLink(finding.fix, finding.severity).label
          }}</ApButton>
        </template>
      </ApListRow>
    </ul>
  </ApPanel>
</template>
