<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApPanel, ApStatTile, plural } from "@/ui";
import { useDraft, stepLabels, steps, type Step } from "./context.ts";

/** A4 What happens: counts, what creating does (option B wording, U2), and the step actions. */
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
const commitLabel = computed(() =>
  count.value === null
    ? "Create spacecraft"
    : `Create ${plural(count.value, "spacecraft", "spacecraft")}`,
);
</script>

<template>
  <ApPanel index="A4" title="What happens">
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-3 gap-px border border-hairline bg-hairline">
        <ApStatTile label="New SC" :value="count" />
        <ApStatTile label="Routing rules" :value="null" caption="added later" />
        <ApStatTile label="Fleet" :value="count === null ? null : fleet + count" />
      </div>
      <ol class="m-0 flex list-none flex-col gap-2 p-0 text-md text-text-3">
        <li class="grid grid-cols-[24px_1fr]">
          <span class="font-mono text-xs text-text-4">01</span> Creates
          {{ count === null ? "the spacecraft" : plural(count, "spacecraft", "spacecraft") }} in one
          step.
        </li>
        <li class="grid grid-cols-[24px_1fr]">
          <span class="font-mono text-xs text-text-4">02</span>
          {{
            profile
              ? `They pin profile ${profile.name} v${profile.version}.`
              : "They pin the profile you choose."
          }}
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
        disabled-reason="Complete this step first."
        @click="emit('go', next)"
        >Continue to {{ stepLabels[next].toLowerCase() }}</ApButton
      >
      <ApButton
        v-else
        variant="primary"
        size="commit"
        disabled
        :disabled-reason="
          canManage
            ? 'Creating spacecraft from the console isn\'t available yet. The batch create endpoint is being built.'
            : 'Only an organization admin can create spacecraft.'
        "
        >{{ commitLabel }}</ApButton
      >
      <p v-if="!next" class="m-0 text-sm text-text-3">
        {{
          canManage
            ? "Creating spacecraft from the console isn't available yet: the batch endpoint is being built. Your draft is kept."
            : "Only an organization admin can create spacecraft."
        }}
      </p>
      <ApButton v-if="previous" @click="emit('go', previous)"
        >Back to {{ stepLabels[previous].toLowerCase() }}</ApButton
      >
    </div>
  </ApPanel>
</template>
