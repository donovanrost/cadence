<script setup lang="ts">
import { ApCallout } from "@cadence/apogee-ui";
import { outcomeRole, type OutcomeTone } from "./outcome-role.ts";

/**
 * The outcome of the person's own act as a callout (a11y B6, #276, ux): its tone and words, and
 * the live role that follows what happened (read politely when it went well, else an alert).
 */
defineProps<{
  outcome: Readonly<{ tone: OutcomeTone; text: string }>;
}>();
</script>

<template>
  <ApCallout :tone="outcome.tone" :role="outcomeRole(outcome.tone)">{{ outcome.text }}</ApCallout>
</template>
