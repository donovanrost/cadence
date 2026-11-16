<script setup lang="ts">
import { ApButton, ApCallout } from "@/ui";
import type { FailureOutcome } from "./actions.ts";

/**
 * A stage or apply failure (failureOutcome) as one callout: its sentence, and its link as the
 * action (U65 'Open the report', U79 'Open change set'), the same on every surface (ux, lead 11-16).
 * An outcome we can't be sure of reads as caution, a refusal as crit, unless the surface says.
 * Extra words go in the default slot; extra buttons in #action, after the link.
 */
const props = defineProps<{
  outcome: FailureOutcome;
  tone?: "crit" | "caution" | "info" | undefined;
}>();
const tone = () => props.tone ?? (props.outcome.changed === null ? "caution" : "crit");
</script>

<template>
  <ApCallout :tone="tone()">
    {{ outcome.sentence }}<template v-if="$slots.default">{{ " " }}<slot /></template>
    <template v-if="outcome.link || $slots.action" #action>
      <ApButton v-if="outcome.link" size="compact" :to="outcome.link.to">{{
        outcome.link.label
      }}</ApButton>
      <slot name="action" />
    </template>
  </ApCallout>
</template>
