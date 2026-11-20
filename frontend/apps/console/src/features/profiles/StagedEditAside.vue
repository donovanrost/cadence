<script setup lang="ts">
import {
  FailureOutcomeCallout,
  type FailureOutcome,
  type FormValues,
  type SchemaField,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApPanel, ApStatTile, outcomeRole, plural } from "@/ui";
import type { PreviewCounts } from "./sectionEdit.ts";

/** Profile.md P4: the dirty fields, the dry run's Changes / Keeps tiles, Check and Stage edit. */
defineProps<{
  dirty: readonly SchemaField[];
  before: FormValues;
  values: FormValues;
  outcome: Readonly<{ tone: "nominal" | "caution" | "crit"; text: string }> | null;
  /** A refused or unclear Stage edit (failureOutcome), with its link. */
  failure: FailureOutcome | null;
  /** From the last Check; null until one has run for these values. */
  counts: PreviewCounts | null;
  busy: boolean;
  /** Why Check is off (fields invalid), or null. */
  invalid: string | null;
  /** Why Stage edit is off, or null. */
  blocked: string | null;
}>();
defineEmits<{ check: []; stage: []; discard: [] }>();
</script>

<template>
  <ApPanel index="P4" title="Staged edit" :meta="plural(dirty.length, 'field')">
    <div class="flex flex-col gap-3">
      <ul class="m-0 list-none p-0 font-mono text-sm">
        <li v-for="f in dirty" :key="f.path" class="py-0.5 text-text-2">
          {{ f.label }} <span class="text-text-4 line-through">{{ before[f.path] || "—" }}</span> →
          <span class="text-readout">{{ values[f.path] || "—" }}</span>
        </li>
      </ul>
      <div v-if="counts" class="grid grid-cols-2 gap-px border border-hairline bg-hairline">
        <ApStatTile label="Changes" :value="counts.changes" unit="spacecraft" />
        <ApStatTile label="Keeps" :value="counts.keeps" unit="spacecraft" />
      </div>
      <ApCallout v-if="outcome" :tone="outcome.tone" :role="outcomeRole(outcome.tone)">{{
        outcome.text
      }}</ApCallout>
      <FailureOutcomeCallout v-if="failure" :outcome="failure" />
      <div class="flex flex-wrap gap-3">
        <ApButton
          :disabled="busy || invalid !== null"
          :disabled-reason="invalid ?? 'Checking…'"
          @click="$emit('check')"
          >Check</ApButton
        >
        <ApButton
          variant="primary"
          :disabled="busy || blocked !== null"
          :disabled-reason="blocked ?? 'Staging…'"
          @click="$emit('stage')"
          >Stage edit</ApButton
        >
        <ApButton variant="ghost" @click="$emit('discard')">Discard</ApButton>
      </div>
    </div>
  </ApPanel>
</template>
