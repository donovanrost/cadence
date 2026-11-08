<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApField, ApPanel, ApStatTile } from "@/ui";
import type { ChangeSet, ConfigState } from "./shapes.ts";

/** K3 Apply: why (required), the apply / review action, gated by config capabilities. */
const props = defineProps<{ config: ConfigState; changeSet: ChangeSet }>();
const why = ref("");
const next = computed(() => props.config.head.revision + 1);
const canApply = computed(() => props.config.permissions.has("config.apply"));
const inReview = computed(() => props.changeSet.state === "in_review");
// Mission policy (ADR-004) decides between applying now and an independent review.
const needsReview = computed(() => props.changeSet.approval_required === true);
const reason = computed(() => {
  if (inReview.value) return `r${next.value} is in review; staging is paused.`;
  if (!canApply.value) return "You can stage changes but not apply them.";
  if (why.value.trim().length < 10) return "Say why (10 characters or more).";
  return needsReview.value
    ? "Requesting review from the console isn't available yet: the submit endpoint is being built."
    : "Applying from the console isn't available yet: the apply endpoint is being built.";
});
</script>

<template>
  <ApPanel index="K3" title="Apply">
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-2 gap-px border border-hairline bg-hairline">
        <ApStatTile label="Changes" :value="changeSet.staged_count" />
        <ApStatTile label="Authors" :value="changeSet.authors.length" />
      </div>
      <ApField
        v-model="why"
        label="Why"
        placeholder="Goes in the revision and the audit log"
        :disabled="inReview || !canApply"
      />
      <ApButton variant="primary" size="commit" disabled :disabled-reason="reason">
        <template v-if="needsReview">Request review</template>
        <template v-else
          >Apply as <span class="font-mono normal-case">r{{ next }}</span></template
        >
      </ApButton>
      <p class="m-0 text-sm text-text-3">{{ reason }}</p>
      <p class="m-0 font-mono text-xs text-text-4 uppercase">
        Atomic · all or nothing ·
        <span class="normal-case">r{{ config.head.revision }}</span> kept for rollback
      </p>
    </div>
  </ApPanel>
</template>
