<script setup lang="ts">
import { computed } from "vue";
import { ApPanel } from "@/ui";
import { ApCheckRows as CheckRows } from "@/ui";
import BatchPreview from "./BatchPreview.vue";
import ServerChecks from "./ServerChecks.vue";
import { batchChecks, checksMeta } from "./checks.ts";
import { useDraft } from "./context.ts";

/** A2 Checks + A3 batch preview (the board's step 04). */
const { proposal, profiles } = useDraft();
const ready = computed(() => {
  const p = proposal();
  return p.status === "ready" ? p : null;
});
const checks = computed(() => {
  const p = ready.value;
  if (!p) return [];
  const profile = profiles().find((c) => c.id === p.profileId) ?? null;
  return batchChecks(p.report, profile);
});

const rows = computed(() =>
  checks.value.map((check) => ({
    key: check.key,
    label: check.label,
    sentence: check.sentence,
    ...(check.verdict === "pass"
      ? { state: "nominal" as const, verdict: "Pass" }
      : check.verdict === "note"
        ? { state: "caution" as const, verdict: "Note" }
        : { state: "crit" as const, verdict: "NO-GO" }),
  })),
);
</script>

<template>
  <ApPanel index="A2" title="Checks" :meta="checksMeta(checks)" flush>
    <CheckRows :rows="rows" />
    <p class="m-0 border-t border-hairline px-4 py-2.5 text-sm text-text-3">
      Checked against this mission's spacecraft in the browser; the server's dry run is below.
    </p>
  </ApPanel>
  <ServerChecks />
  <BatchPreview v-if="ready" :rows="ready.report.rows" />
</template>
