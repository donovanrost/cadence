<script setup lang="ts">
import { computed } from "vue";
import { ApListRow, ApPanel } from "@/ui";
import { reasonText, type PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";

/** A · Demand: only spacecraft whose rule isn't met (ScheduleFlow R01: start from demand). */
const props = defineProps<{
  plan: PlanDetail;
  nameOf: (id: string | null) => SpacecraftName | null;
  focused: string | null;
}>();
defineEmits<{ focus: [spacecraftId: string] }>();

const unmet = computed(() => props.plan.demand.spacecraft.filter((s) => !s.rule_met));
const ruleText = computed(() =>
  [...new Set(props.plan.demand.rules.map((r) => r.text))].slice(0, 2),
);
function why(reasons: readonly string[], have: number): string {
  if (have === 0 && reasons.length > 0)
    return `No window can cover it: ${reasonText(reasons[0] ?? "").toLowerCase()}`;
  return reasons.length > 0 ? reasons.map(reasonText).join(" · ") : "Rule not met";
}
</script>

<template>
  <ApPanel
    index="A"
    title="Demand"
    :meta="unmet.length > 0 ? `${unmet.length} not covered` : 'All covered'"
    pane
    flush
  >
    <ul v-if="unmet.length > 0" class="m-0 list-none p-0">
      <ApListRow
        v-for="row in unmet"
        :key="row.spacecraft_id"
        :state="row.contacts.have === 0 ? 'crit' : 'caution'"
        :sentence="why(row.reasons, row.contacts.have)"
        :meta="`${row.contacts.have} / ${row.contacts.need ?? '?'} contacts`"
      >
        <template #title>
          <button
            type="button"
            class="max-md:hit-44 cursor-pointer border-0 bg-transparent p-0 text-left font-mono text-base font-semibold text-readout hover:underline"
            :aria-pressed="focused === row.spacecraft_id"
            @click="$emit('focus', row.spacecraft_id)"
          >
            {{ nameOf(row.spacecraft_id)?.name ?? row.spacecraft_id }}
          </button>
        </template>
      </ApListRow>
    </ul>
    <p v-else class="m-0 px-4 py-3 text-md text-text-3">
      Every spacecraft meets its rule in this draft.
    </p>
    <p
      v-for="text in ruleText"
      :key="text"
      class="m-0 border-t border-hairline px-4 py-2.5 font-mono text-xs text-text-4 uppercase"
    >
      From requirement: {{ text }}
    </p>
  </ApPanel>
</template>
