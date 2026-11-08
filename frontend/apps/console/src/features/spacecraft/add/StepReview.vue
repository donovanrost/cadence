<script setup lang="ts">
import { computed } from "vue";
import { ApPanel, ApTag } from "@/ui";
import BatchPreview from "./BatchPreview.vue";
import { batchChecks, checksMeta, type CheckVerdict } from "./checks.ts";
import { useDraft } from "./context.ts";
import { profileChoices } from "./draft.ts";

/** A2 Checks + A3 batch preview (the board's step 04). */
const { proposal, directory } = useDraft();
const ready = computed(() => {
  const p = proposal();
  return p.status === "ready" ? p : null;
});
const checks = computed(() => {
  const p = ready.value;
  if (!p) return [];
  const profile = profileChoices(directory()).find((c) => c.id === p.profileId) ?? null;
  return batchChecks(p.report, profile);
});

const tag = (verdict: CheckVerdict) =>
  verdict === "pass"
    ? ({ state: "nominal", label: "Pass" } as const)
    : verdict === "note"
      ? ({ state: "caution", label: "Note" } as const)
      : ({ state: "crit", label: "NO-GO" } as const);
</script>

<template>
  <ApPanel index="A2" title="Checks" :meta="checksMeta(checks)" flush>
    <ul class="m-0 list-none p-0">
      <li
        v-for="check in checks"
        :key="check.key"
        class="grid grid-cols-[110px_minmax(0,1fr)_auto] items-center gap-3 border-t border-hairline px-4 py-2.5 first:border-t-0"
        :class="{
          'bg-[var(--apogee-wash-caution)]': check.verdict === 'note',
          'bg-[var(--apogee-wash-crit)]': check.verdict === 'nogo',
        }"
      >
        <span class="ap-label">{{ check.label }}</span>
        <span class="text-md text-readout">{{ check.sentence }}</span>
        <ApTag v-bind="tag(check.verdict)" />
      </li>
    </ul>
    <p class="m-0 border-t border-hairline px-4 py-2.5 text-sm text-text-3">
      Checked against this mission's spacecraft in the browser. Cadence checks again when the batch
      is created.
    </p>
  </ApPanel>
  <BatchPreview v-if="ready" :rows="ready.report.rows" />
</template>
