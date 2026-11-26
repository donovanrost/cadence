<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApCallout, ApPageHeader, ApRemote, ApTabLinks, plural } from "@/ui";
import { contactsSections } from "@/features/contacts/index.ts";
import DailyPanel from "./DailyPanel.vue";
import LostPanel from "./LostPanel.vue";
import ReviewControls from "./ReviewControls.vue";
import SummarySection from "./SummarySection.vue";
import { fetchDaily, fetchSummary } from "./api.ts";
import { freshnessMeta, headline } from "./format.ts";
import { useLostRows } from "./useLostRows.ts";
import { useReviewExport } from "./useReviewExport.ts";
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
const lost = useLostRows(key);
const daily = useRemoteQuery(key, fetchDaily);
useMissionInvalidation(missionId, ["pass_results"], () => {
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
const exporter = useReviewExport(
  key,
  computed(() => scope.value.mission.slug),
  s,
);
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
      <ReviewControls
        :span="win.span.value"
        :day-at="dayAt"
        :can-export="s !== null"
        :exporting="exporter.busy.value"
        @span="win.set({ span: $event })"
        @day="pickDay"
        @export="exporter.run"
      />
    </ApPageHeader>
    <ApTabLinks :links="contactsSections" active="review" label="Contacts sections" />
    <ApCallout v-if="exporter.failure.value" tone="caution" role="alert">{{
      exporter.failure.value
    }}</ApCallout>
    <SummarySection :state="summary.state.value" @retry="summary.refetch" />
    <ApRemote :state="daily.state.value" loading-label="Loading 30 days…" @retry="daily.refetch">
      <template #default="{ value }"><DailyPanel :daily="value" :day="win.day.value" /></template>
    </ApRemote>
    <ApRemote :state="lost.state.value" loading-label="Loading lost passes…" @retry="lost.refetch">
      <template #default="{ value }"
        ><LostPanel
          :rows="value.items"
          :total="value.meta.total"
          :has-more="value.next !== null"
          :loading="lost.moreBusy.value"
          :failed="lost.moreError.value !== null"
          @more="lost.more"
      /></template>
    </ApRemote>
  </div>
</template>
