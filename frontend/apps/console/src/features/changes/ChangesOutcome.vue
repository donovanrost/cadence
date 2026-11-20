<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRuntimeStatus } from "@/shell";
import { ApButton, ApCallout, outcomeRole, plural } from "@/ui";
import type { SubmitResult } from "./actions.ts";
import { savedOnlyText } from "./nothingRunning.ts";
import { configRuntime, outcomeRuntime, outcomeText } from "./runtime.ts";

/** What staging elsewhere or submitting here just did (ux: say what happened and when it lands). */
const props = defineProps<{
  outcome: SubmitResult | null;
  /** Spacecraft staged from Add spacecraft, shown once. */
  stagedNotice: number | null;
  /** The revision the open set applies as, when known. */
  next: number | null;
}>();
/** After Apply: the live runtime (lead's useRuntimeStatus) over the submit's snapshot (ux). */
const runtimeStatus = useRuntimeStatus();
const live = computed(() =>
  runtimeStatus.value === undefined ? undefined : configRuntime(runtimeStatus.value),
);
const sawApplying = ref(false);
watch(
  () => props.outcome,
  () => (sawApplying.value = false),
);
watch(live, (l) => {
  if (l === "applying") sawApplying.value = true;
});
const applied = computed(() => {
  const o = props.outcome;
  if (o?.state !== "applied") return null;
  // U93: only when the server says no activation exists (never from runtime not_applicable).
  if (o.has_active_configuration === false)
    return {
      tone: "info" as const,
      text: savedOnlyText(o.revision, o.staged_count),
    };
  const runtime = outcomeRuntime(o.runtime, live.value, sawApplying.value);
  return outcomeText(
    o.revision,
    plural(o.staged_count, "change"),
    runtime,
    runtimeStatus.value?.reason ?? null,
  );
});
</script>

<template>
  <ApCallout v-if="stagedNotice !== null && next !== null && !outcome" tone="nominal">
    {{ plural(stagedNotice, "spacecraft", "spacecraft") }} staged. They're created when this change
    set is applied as <span class="font-mono">r{{ next }}</span
    >.
  </ApCallout>
  <ApCallout
    v-if="applied"
    data-changes-outcome
    :tone="applied.tone"
    :role="outcomeRole(applied.tone)"
  >
    {{ applied.text }}
    <template #action
      ><ApButton size="compact" :to="{ name: 'setup.revisions' }"
        >View revisions</ApButton
      ></template
    >
  </ApCallout>
  <ApCallout v-else-if="outcome?.state === 'in_review'" data-changes-outcome tone="info">
    Sent for review. An org member who didn't stage any of these changes approves or sends it back.
  </ApCallout>
  <ApCallout v-else-if="outcome?.state === 'open'" data-changes-outcome tone="info">
    Sent back to the authors with your comment.
  </ApCallout>
</template>
