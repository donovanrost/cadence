<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";
import { ApButton, ApListRow } from "@/ui";
import type { SpacecraftName } from "./names.ts";

/**
 * A · Demand's lead rows: rejected, failed, lost, not-sent and expired passes, each with ux's
 * reason sentence and its next step (ScheduleFlow K1 booking reasons, f05d68e9).
 */
type Row = Readonly<{
  snapshotId: string;
  spacecraftId: string | null;
  sentence: string;
  next: "replan" | "account" | "setup" | null;
  code: string | null;
}>;
const props = defineProps<{
  rows: readonly Row[];
  planId: string;
  nameOf: (id: string | null) => SpacecraftName | null;
}>();
defineEmits<{ focus: [spacecraftId: string] }>();
const NEXT = {
  replan: "Re-plan",
  account: "Check provider account",
  setup: "Fix in Setup",
} as const;
function nextTo(next: NonNullable<Row["next"]>): RouteLocationRaw {
  if (next === "replan") return { name: "ops.contacts.replan", query: { plan: props.planId } };
  if (next === "account") return { name: "org.provider-accounts" };
  return { name: "setup.stations.providers" };
}
</script>

<template>
  <ul v-if="rows.length > 0" class="m-0 list-none border-b border-hairline p-0">
    <ApListRow v-for="row in rows" :key="row.snapshotId" state="caution" :sentence="row.sentence">
      <template #title>
        <button
          type="button"
          class="max-md:hit-44 cursor-pointer border-0 bg-transparent p-0 text-left font-mono text-base font-semibold text-readout hover:underline"
          :title="row.code ?? undefined"
          @click="row.spacecraftId && $emit('focus', row.spacecraftId)"
        >
          {{ nameOf(row.spacecraftId)?.name ?? row.spacecraftId ?? "Unknown spacecraft" }}
        </button>
      </template>
      <template v-if="row.next" #action>
        <ApButton variant="ghost" size="compact" :to="nextTo(row.next)">{{
          NEXT[row.next]
        }}</ApButton>
      </template>
    </ApListRow>
  </ul>
</template>
