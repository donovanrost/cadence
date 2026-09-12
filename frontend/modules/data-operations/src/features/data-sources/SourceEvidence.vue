<script setup lang="ts">
import { computed } from "vue";
import type { SourceModel, PageKey, Page, SourceAction, Job } from "./native-contract";
import SourcePageControls from "./SourcePageControls.vue";
const props = defineProps<{
  selected: NonNullable<SourceModel["selected"]>;
  disabled: boolean;
  manage: boolean;
}>();
defineEmits<{ page: [key: PageKey, page: number]; job: [action: SourceAction, job: Job] }>();
const eventFields = ["id", "source_id", "type", "status", "actor_id", "occurred_at"];
const observationFields = [
  "id",
  "source_id",
  "binding_id",
  "logical_source",
  "realm",
  "dataset",
  "replay_run_id",
  "observed_at",
  "reason",
];
const sections = computed(
  () =>
    [
      {
        key: "events_page",
        name: "Source history",
        fields: eventFields,
        rows: props.selected.events,
      },
      {
        key: "binding_events_page",
        name: "Selected binding history",
        fields: [...eventFields, "binding_id", "previous_source_id", "version"],
        rows: props.selected.binding_events,
      },
      {
        key: "health_page",
        name: "Observed health",
        fields: [...observationFields, "state", "key", "last_seen_at", "transitions"],
        rows: props.selected.health,
      },
      {
        key: "health_events_page",
        name: "Health history",
        fields: [...observationFields, "state"],
        rows: props.selected.health_events,
      },
      {
        key: "watermarks_page",
        name: "Watermarks",
        fields: [
          ...observationFields,
          "key",
          "complete_through",
          "latest_receipt_time",
          "retention_starts_at",
          "confidence",
          "sample_count",
          "last_seen_at",
        ],
        rows: props.selected.watermarks,
      },
    ] as { key: PageKey; name: string; fields: string[]; rows: Page<Record<string, unknown>> }[],
);
const labels: Record<string, string> = {
  id: "Event",
  source_id: "Source",
  type: "Event type",
  status: "Status",
  actor_id: "Actor",
  occurred_at: "Occurred",
  binding_id: "Binding",
  previous_source_id: "Previous source",
  version: "Version",
  logical_source: "Logical source",
  realm: "Realm",
  dataset: "Dataset",
  replay_run_id: "Replay run",
  observed_at: "Observed",
  reason: "Reason",
  state: "Health",
  key: "Observation key",
  last_seen_at: "Last seen",
  transitions: "Transitions",
  complete_through: "Complete through",
  latest_receipt_time: "Latest receipt",
  retention_starts_at: "Retention starts",
  confidence: "Confidence",
  sample_count: "Samples",
};
</script>
<template>
  <section
    v-for="section in sections"
    :id="'sources-' + section.key"
    :key="section.key"
    class="min-w-0 space-y-3 border border-base-300 bg-base-100 p-4"
    :aria-label="section.name"
  >
    <h3 class="text-sm font-semibold">{{ section.name }}</h3>
    <p v-if="!section.rows.entries.length" class="text-sm text-base-content/60">
      {{
        section.key === "binding_events_page" && !selected.binding
          ? "Select a binding to inspect its history."
          : "No records on this page."
      }}
    </p>
    <ol class="space-y-3">
      <li
        v-for="row in section.rows.entries"
        :key="String(row.key ?? row.id)"
        class="border border-base-300 p-3"
      >
        <dl class="grid min-w-0 gap-x-4 gap-y-2 text-xs sm:grid-cols-2">
          <div v-for="key in section.fields" :key="key" class="min-w-0">
            <dt class="text-base-content/60">{{ labels[key] ?? key }}</dt>
            <dd class="break-all font-mono">{{ row[key] ?? "Not recorded" }}</dd>
          </div>
        </dl>
      </li>
    </ol>
    <SourcePageControls
      :id="'sources-' + section.key"
      :label="section.name"
      :page="section.rows"
      :disabled="disabled"
      @change="$emit('page', section.key, $event)"
    />
  </section>
  <section
    id="sources-jobs"
    aria-label="Deployment jobs"
    class="min-w-0 space-y-3 border border-base-300 bg-base-100 p-4"
  >
    <h3 class="text-sm font-semibold">Deployment jobs</h3>
    <p v-if="!selected.jobs.entries.length" class="text-sm text-base-content/60">
      No deployment jobs on this page.
    </p>
    <ol class="space-y-3">
      <li
        v-for="job in selected.jobs.entries"
        :key="job.id"
        class="space-y-2 border border-base-300 p-3 text-xs"
      >
        <p class="break-all font-mono">{{ job.id }} · run {{ job.run_id }}</p>
        <p>
          {{ job.type }} · {{ job.operation ?? "Operation not recorded" }} · {{ job.status }} ·
          attempt {{ job.attempts }}
        </p>
        <p>
          Started {{ job.started_at ?? "Not recorded" }} · completed
          {{ job.completed_at ?? "Not recorded" }}
        </p>
        <p v-if="job.failure_recorded">A failure was recorded.</p>
        <div v-if="manage" class="flex flex-wrap gap-2">
          <button
            :id="'source-job-retry-' + job.id"
            type="button"
            class="btn btn-xs btn-outline"
            :disabled="disabled || job.status !== 'failed'"
            @click="$emit('job', 'retry-deployment-run', job)"
          >
            Retry deployment
          </button>
          <button
            :id="'source-job-requeue-' + job.id"
            type="button"
            class="btn btn-xs btn-outline"
            :disabled="disabled || job.status !== 'running'"
            @click="$emit('job', 'requeue-deployment-run', job)"
          >
            Requeue job
          </button>
        </div>
      </li>
    </ol>
    <SourcePageControls
      id="sources-jobs_page"
      label="Deployment jobs"
      :page="selected.jobs"
      :disabled="disabled"
      @change="$emit('page', 'jobs_page', $event)"
    />
  </section>
</template>
