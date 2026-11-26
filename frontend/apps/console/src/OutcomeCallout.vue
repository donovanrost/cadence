<script setup lang="ts">
import { announcePolite, ApCallout } from "@cadence/apogee-ui";
import { watch } from "vue";
import { outcomeRole, type OutcomeTone } from "./outcome-role.ts";

/**
 * The outcome of the person's own act as a callout (a11y B6, #276, ux). Anything that went wrong
 * is an alert. A success is said once through the kit's polite region (announcePolite), because a
 * status region inserted already holding its words isn't reliably read; the callout itself then
 * has no live role, so a screen reader that does read it doesn't say it twice.
 * announcePolite has one timer for the page (lead, #433): two successes within its delay keep only
 * the last, which suits these (each replaces the one before it on screen).
 * The watch is by object: give each act's outcome a new object (a ref set per act, or a computed),
 * so a repeated success is said again and a re-render never says it twice (lead, #604).
 * The default slot shows the same words with markup (a mono revision); `outcome.text` is what's
 * announced, so the two must say the same thing (ux, #604). Buttons go in #action.
 */
const props = defineProps<{ outcome: Readonly<{ tone: OutcomeTone; text: string }> }>();
watch(
  () => props.outcome,
  (o) => {
    if (outcomeRole(o.tone) === "status") announcePolite(o.text);
  },
  { immediate: true },
);
</script>

<template>
  <ApCallout :tone="outcome.tone" :role="outcomeRole(outcome.tone) === 'status' ? 'none' : 'alert'"
    ><slot>{{ outcome.text }}</slot>
    <template v-if="$slots.action" #action><slot name="action" /></template>
  </ApCallout>
</template>
