<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApPanel, ApStatTile, plural } from "@/ui";
import StageBatchButton from "./StageBatchButton.vue";
import { useDraft, stepLabels, steps, type Step } from "./context.ts";

/** A4 What happens: counts, what staging does (change sets, Changes.md §1), and the step actions. */
const props = defineProps<{ step: Step; canManage: boolean }>();
const emit = defineEmits<{ go: [step: Step] }>();
const { proposal, directory, profiles } = useDraft();

const ready = computed(() => {
  const p = proposal();
  return p.status === "ready" ? p : null;
});
const count = computed(() => ready.value?.report.rows.length ?? null);
const fleet = computed(() => directory().spacecraft.length);
const profile = computed(() => profiles().find((c) => c.id === ready.value?.profileId));
const index = computed(() => steps.indexOf(props.step));
const next = computed(() => steps[index.value + 1] ?? null);
const previous = computed(() => (index.value > 0 ? steps[index.value - 1] : null));
const blockedAt = computed(() => {
  const p = proposal();
  return p.status === "incomplete" ? steps.indexOf(p.step) : steps.length;
});
const continueReason = computed(() => {
  const p = proposal();
  if (p.status !== "incomplete" || steps.indexOf(p.step) > index.value) return null;
  const first = Object.values(p.errors).find((message) => message !== undefined);
  return first ?? "Complete this step first.";
});
</script>

<template>
  <ApPanel index="A4" title="What happens">
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-3 gap-px border border-hairline bg-hairline">
        <ApStatTile label="New spacecraft" :value="count" />
        <ApStatTile label="Routing rules" :value="null" caption="added later" />
        <ApStatTile label="Fleet" :value="count === null ? null : fleet + count" />
      </div>
      <ol class="m-0 flex list-none flex-col gap-2 p-0 text-md text-text-3">
        <li class="grid grid-cols-[24px_1fr]">
          <span class="font-mono text-xs text-text-4">01</span> The batch joins the staged changes.
          Nothing is live yet.
        </li>
        <li class="grid grid-cols-[24px_1fr]">
          <span class="font-mono text-xs text-text-4">02</span> Applying the change set creates
          {{ count === null ? "them" : plural(count, "spacecraft", "spacecraft") }} together{{
            profile ? `, pinned to ${profile.name} v${profile.version}` : ""
          }}.
        </li>
        <li class="grid grid-cols-[24px_1fr]">
          <span class="font-mono text-xs text-text-4">03</span> Each one shows as “awaiting first
          AOS” on the console until it's heard, never as nominal.
        </li>
      </ol>
      <ApButton
        v-if="next"
        variant="primary"
        size="commit"
        :disabled="blockedAt <= index"
        :disabled-reason="continueReason ?? 'Complete this step first.'"
        @click="emit('go', next)"
        >Continue to {{ stepLabels[next].toLowerCase() }}</ApButton
      >
      <p v-if="next && blockedAt <= index" class="m-0 font-mono text-xs text-text-4 uppercase">
        {{ continueReason }}
      </p>
      <StageBatchButton v-if="!next" :can-manage="canManage" />
      <ApButton v-if="previous" @click="emit('go', previous)"
        >Back to {{ stepLabels[previous].toLowerCase() }}</ApButton
      >
    </div>
  </ApPanel>
</template>
