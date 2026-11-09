<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApStatStrip, ApStatTile } from "@/ui";
import type { PlanDetail } from "./api.ts";
import { planPrimary } from "./plan-primary.ts";

/** K1 footer: totals + the one primary for the plan's state (plan-primary.ts). */
const props = defineProps<{
  plan: PlanDetail;
  isAdmin: boolean;
  busy: boolean;
  /** Replaces the sheet primary's label (K2: "Apply r42 · book N passes"). */
  sheetLabel?: string | undefined;
}>();
defineEmits<{ sheet: []; execute: [] }>();
const primary = computed(() => planPrimary(props.plan, props.isAdmin));
const conflicts = computed(() => props.plan.conflicts.length);
</script>

<template>
  <footer class="flex flex-none flex-wrap items-stretch gap-3 border-t border-hairline pt-3">
    <ApStatStrip :columns="4" label="Plan totals" class="min-w-[min(100%,520px)] flex-1">
      <ApStatTile label="Passes" :value="plan.counts.passes" />
      <ApStatTile label="Minutes" :value="plan.counts.minutes" />
      <ApStatTile
        label="Rule met"
        :value="plan.demand.rule_met"
        :denominator="plan.demand.rule_total"
        :state="plan.demand.rule_met < plan.demand.rule_total ? 'caution' : 'nominal'"
      />
      <ApStatTile
        label="Conflicts"
        :value="conflicts"
        :state="conflicts > 0 ? 'crit' : 'neutral'"
      />
    </ApStatStrip>
    <div class="flex min-w-[240px] flex-col justify-center gap-1.5">
      <template v-if="primary.kind === 'sheet'">
        <ApButton variant="primary" size="commit" :disabled="busy" @click="$emit('sheet')">{{
          sheetLabel ?? primary.label
        }}</ApButton>
      </template>
      <ApButton
        v-else-if="primary.kind === 'execute'"
        variant="primary"
        size="commit"
        :disabled="busy"
        @click="$emit('execute')"
        >{{ primary.label }}</ApButton
      >
      <ApButton
        v-else-if="primary.kind === 'link'"
        variant="primary"
        size="commit"
        :to="primary.to"
        >{{ primary.label }}</ApButton
      >
      <template v-else-if="primary.kind === 'blocked'">
        <ApButton variant="primary" size="commit" disabled :disabled-reason="primary.reason">{{
          primary.label
        }}</ApButton>
        <p class="m-0 max-w-[320px] text-sm text-text-3">{{ primary.reason }}</p>
      </template>
      <p v-else-if="primary.note" class="m-0 max-w-[320px] text-md text-text-3">
        {{ primary.note }}
      </p>
    </div>
  </footer>
</template>
