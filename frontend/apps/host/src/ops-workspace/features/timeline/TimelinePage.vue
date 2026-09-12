<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import TimelinePanel from "./TimelinePanel.vue";
import { readTimeline } from "./contracts";
const props = defineProps<{
  snapshot: unknown;
  organizationId: unknown;
  missionId: unknown;
  navigate: (href: string) => void;
  refresh: () => Promise<void>;
}>();
const crashed = ref(false);
watch(
  () => [props.snapshot, props.organizationId, props.missionId],
  () => (crashed.value = false),
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const model = computed(() => {
  const value = props.snapshot as Record<string, unknown> | null;
  const context = value?.context as Record<string, unknown> | undefined;
  if (
    !value ||
    value.version !== 1 ||
    value.page !== "timeline" ||
    value.status !== "ready" ||
    !context ||
    context.organization_id !== props.organizationId ||
    context.mission_id !== props.missionId
  )
    return null;
  try {
    return readTimeline(value.data, props.organizationId, props.missionId);
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="core-timeline-page">
    <div
      v-if="crashed || !model"
      id="core-timeline-error"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>The mission timeline is unavailable.</p>
      <button id="core-timeline-retry" type="button" class="btn btn-sm mt-4" @click="refresh">
        Retry
      </button>
    </div>
    <TimelinePanel v-else :model="model" :navigate="navigate" :refresh="refresh" />
  </section>
</template>
