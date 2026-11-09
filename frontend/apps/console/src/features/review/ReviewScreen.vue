<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApCallout, ApPageHeader, ApRemote, ApSegmented, ApTimePicker, plural } from "@/ui";
import CausesPanel from "./CausesPanel.vue";
import DailyPanel from "./DailyPanel.vue";
import LostPanel from "./LostPanel.vue";
import ReviewStrip from "./ReviewStrip.vue";
import StationsPanel from "./StationsPanel.vue";
import { fetchDaily, fetchLost, fetchSummary, type Span } from "./api.ts";
import { freshnessMeta, headline, provisionalText } from "./format.ts";
import { useReviewWindow } from "./useReviewWindow.ts";

/** K3 · Close the books (reading page). Spec: ux/screens/ScheduleFlow.md §K3; data: S9. */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const win = useReviewWindow();
const key = computed(() => ({
  missionId: missionId.value,
  day: win.day.value,
  span: win.span.value,
}));
const summary = useRemoteQuery(key, fetchSummary);
const lost = useRemoteQuery(key, fetchLost);
const daily = useRemoteQuery(key, fetchDaily);
// TODO(lead): "pass_results" once it's in missionResources; contact changes cover it until then.
useMissionInvalidation(missionId, ["contacts"], () => {
  summary.refetch();
  lost.refetch();
  daily.refetch();
});
const s = computed(() =>
  summary.state.value.status === "ready" ? summary.state.value.value : null,
);
const label = computed(() => {
  const plans = s.value?.plans ?? [];
  const plan =
    plans.length === 1
      ? `Plan r${plans[0]?.version}`
      : plans.length > 1
        ? plural(plans.length, "plan")
        : null;
  return ["Pass review", plan, s.value ? plural(s.value.freshness.length, "provider") : null]
    .filter(Boolean)
    .join(" · ");
});
const spans = [
  { value: "day", label: "Day" },
  { value: "week", label: "Week" },
  { value: "month", label: "Month" },
];
const dayAt = computed(() => Date.parse(`${win.day.value}T00:00:00Z`));
const pickDay = (t: number | null) =>
  t !== null && win.set({ day: new Date(t).toISOString().slice(0, 10) });
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader :label="label" :title="s ? headline(s).text : 'Pass review'" size="reading">
      <template v-if="s" #subtitle>
        <p
          class="m-0 font-mono text-sm uppercase"
          :class="s.provisional ? 'text-stale-text' : 'text-text-3'"
        >
          {{ freshnessMeta(s) }}
        </p>
      </template>
      <div class="flex flex-wrap items-end gap-3">
        <ApSegmented
          :model-value="win.span.value"
          label="Span"
          :options="spans"
          @update:model-value="win.set({ span: $event as Span })"
        />
        <div class="w-[200px]">
          <ApTimePicker
            :model-value="dayAt"
            label="Ending"
            date-only
            @update:model-value="pickDay"
          />
        </div>
      </div>
    </ApPageHeader>
    <ApRemote
      :state="summary.state.value"
      loading-label="Loading pass results…"
      @retry="summary.refetch"
    >
      <template #default="{ value }">
        <ApCallout v-if="provisionalText(value)" tone="caution">{{
          provisionalText(value)
        }}</ApCallout>
        <ReviewStrip :summary="value" />
        <div class="grid grid-cols-1 gap-4 console:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
          <StationsPanel :lines="value.by_station" />
          <CausesPanel :causes="value.by_cause" />
        </div>
      </template>
    </ApRemote>
    <ApRemote :state="daily.state.value" loading-label="Loading 30 days…" @retry="daily.refetch">
      <template #default="{ value }"><DailyPanel :daily="value" :day="win.day.value" /></template>
    </ApRemote>
    <ApRemote :state="lost.state.value" loading-label="Loading lost passes…" @retry="lost.refetch">
      <template #default="{ value }"><LostPanel :page="value" /></template>
    </ApRemote>
  </div>
</template>
