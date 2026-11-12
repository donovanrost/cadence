<script setup lang="ts">
import { ApButton, ApCallout, plural } from "@/ui";
import type { SubmitResult } from "./actions.ts";

/** What staging elsewhere or submitting here just did (ux: say what happened and when it lands). */
defineProps<{
  outcome: SubmitResult | null;
  /** Spacecraft staged from Add spacecraft, shown once. */
  stagedNotice: number | null;
  /** The revision the open set applies as, when known. */
  next: number | null;
}>();
</script>

<template>
  <ApCallout v-if="stagedNotice !== null && next !== null && !outcome" tone="nominal">
    {{ plural(stagedNotice, "spacecraft", "spacecraft") }} staged. They're created when this change
    set is applied as <span class="font-mono">r{{ next }}</span
    >.
  </ApCallout>
  <ApCallout v-if="outcome?.state === 'applied'" tone="nominal">
    <span class="font-mono normal-case">r{{ outcome.revision }}</span> applied ·
    {{ plural(outcome.staged_count, "change")
    }}<template v-if="outcome.runtime === 'degraded'">
      · the runtime hasn't converged on
      {{ outcome.degraded_partitions.length }} partitions</template
    >
    <template #action
      ><ApButton size="compact" :to="{ name: 'setup.revisions' }"
        >View revisions</ApButton
      ></template
    >
  </ApCallout>
  <ApCallout v-else-if="outcome?.state === 'in_review'" tone="info">
    Sent for review. An org member who didn't stage any of these changes approves or sends it back.
  </ApCallout>
  <ApCallout v-else-if="outcome?.state === 'open'" tone="info">
    Sent back to the authors with your comment.
  </ApCallout>
</template>
