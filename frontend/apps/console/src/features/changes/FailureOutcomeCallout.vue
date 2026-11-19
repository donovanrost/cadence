<script setup lang="ts">
import { ApButton, ApCallout } from "@/ui";
import type { RefusalOutcome } from "./refusals.ts";

/**
 * A stage or apply failure (failureOutcome) as one callout: its sentence, and its link as the
 * action (U65 'Open the report', U79 'Open change set'), the same on every surface (ux, lead 11-16).
 * An outcome we can't be sure of reads as caution, a refusal as crit, unless the surface says.
 * U82: an in-use refusal also lists what uses the thing, line by line, then its closing sentence.
 * Extra words go in the default slot; extra buttons in #action, after the link.
 */
const props = defineProps<{
  outcome: RefusalOutcome;
  tone?: "crit" | "caution" | "info" | undefined;
}>();
const tone = () => props.tone ?? (props.outcome.changed === null ? "caution" : "crit");
</script>

<template>
  <ApCallout :tone="tone()">
    {{ outcome.sentence }}<template v-if="$slots.default">{{ " " }}<slot /></template>
    <ul v-if="outcome.uses?.length" class="m-0 my-1 ps-5">
      <li v-for="line in outcome.uses" :key="line.label">
        {{ line.label }}:
        <template v-for="(item, i) in line.items" :key="item.text"
          >{{ i > 0 ? ", " : ""
          }}<RouterLink
            v-if="item.to"
            :to="item.to"
            class="text-primary no-underline hover:underline"
            >{{ item.text }}</RouterLink
          ><template v-else>{{ item.text }}</template></template
        ><template v-if="line.more > 0"> and {{ line.more }} more</template>
      </li>
    </ul>
    <template v-if="outcome.closing">{{ outcome.closing }}</template>
    <details v-if="outcome.technical" class="mt-1 text-sm">
      <summary class="ap-label cursor-pointer">Technical details</summary>
      <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ outcome.technical }}</p>
    </details>
    <template v-if="outcome.link || $slots.action" #action>
      <ApButton v-if="outcome.link" size="compact" :to="outcome.link.to">{{
        outcome.link.label
      }}</ApButton>
      <slot name="action" />
    </template>
  </ApCallout>
</template>
