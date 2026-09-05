<script setup lang="ts">
import ActivityTimeline from "./ActivityTimeline.vue";
import VersionHistorySummary from "./VersionHistorySummary.vue";

type Attributes = Record<string, string>;
type ActivityTimelinePresentation = InstanceType<typeof ActivityTimeline>["$props"]["presentation"];
type VersionHistorySummaryPresentation = InstanceType<
  typeof VersionHistorySummary
>["$props"]["presentation"];

type ChildPresentation<T> = {
  root: { attrs: Attributes };
  presentation: T;
};

type Presentation = {
  root: { attrs: Attributes };
  version_history_summary: ChildPresentation<VersionHistorySummaryPresentation>;
  activity_timeline: ChildPresentation<ActivityTimelinePresentation>;
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <div v-bind="presentation.version_history_summary.root.attrs">
      <VersionHistorySummary :presentation="presentation.version_history_summary.presentation" />
    </div>
    <div v-bind="presentation.activity_timeline.root.attrs">
      <ActivityTimeline :presentation="presentation.activity_timeline.presentation" />
    </div>
  </div>
</template>
