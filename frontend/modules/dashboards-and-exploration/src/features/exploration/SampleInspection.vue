<script setup lang="ts">
import { computed } from "vue";
import type { SampleInspection, SampleValue } from "./contracts";
const props = defineProps<{ inspection: SampleInspection; sampleId: string; pending: boolean }>();
defineEmits<{ clear: [] }>();
const sample = computed(() =>
  props.inspection.status === "ready" ? props.inspection.sample : null,
);
const messages = {
  not_selected: "Select a sample to inspect its stored record.",
  not_found: "The physical sample was not found within this query’s source and scope.",
  ambiguous:
    "More than one physical record matches. Narrow the source and window, or select a row using receipt time.",
  unsupported:
    "This source or query context does not support physical sample inspection. The query results remain available.",
  timeout:
    "Physical sample inspection timed out. Read again to retry; the query results remain available.",
  unavailable:
    "The physical sample could not be inspected. No replacement sample or alternate source was used.",
};
function literal(value: SampleValue) {
  if (value.state === "ready") return value.text;
  return {
    not_recorded: "Not recorded",
    limited: "Value exceeds display limits",
    unsupported: "Value format cannot be displayed",
  }[value.state];
}
const references = computed(() =>
  sample.value
    ? [
        ["Source endpoint", sample.value.source.source_endpoint_id],
        ["Spacecraft", sample.value.spacecraft_id],
        ["Replay run", sample.value.source.replay_run_id],
        ["Packet", sample.value.record.packet_id],
        ["Raw evidence", sample.value.record.evidence_id],
        ["Packet definition", sample.value.record.packet_definition_id],
        ["Definition version", sample.value.record.packet_definition_version],
      ]
    : [],
);
</script>
<template>
  <aside
    id="exploration-selection"
    aria-labelledby="exploration-sample-title"
    class="overflow-hidden rounded border border-base-300 border-l-2 border-l-primary bg-base-200/30"
  >
    <header
      class="flex flex-wrap items-start justify-between gap-3 border-b border-base-300 px-4 py-3"
    >
      <div class="min-w-0 flex-1">
        <h2
          id="exploration-sample-title"
          class="text-xs font-semibold uppercase tracking-widest text-base-content/70"
        >
          Selected sample
        </h2>
        <code id="exploration-sample-id" class="mt-1 block break-all font-mono text-sm">{{
          sampleId
        }}</code>
      </div>
      <button
        id="exploration-clear-selection"
        class="btn btn-xs btn-ghost"
        type="button"
        :disabled="pending"
        @click="$emit('clear')"
      >
        Clear selection
      </button>
    </header>
    <div v-if="sample" id="exploration-sample-details" class="space-y-4 p-4">
      <div class="flex flex-wrap items-center gap-2 text-xs">
        <span class="font-medium">{{ sample.point_name ?? sample.point_id }}</span>
        <span class="text-base-content/50" aria-hidden="true">·</span>
        <span class="uppercase tracking-wide text-base-content/70">{{ sample.source.realm }}</span>
        <span
          id="exploration-sample-quality"
          class="rounded border px-2 py-0.5"
          :class="
            sample.quality === 'bad'
              ? 'border-error/40 text-error'
              : sample.quality === 'suspect'
                ? 'border-warning/40 text-warning'
                : 'border-success/40 text-success'
          "
        >
          Quality: {{ sample.quality }}
        </span>
      </div>
      <dl class="grid gap-3 sm:grid-cols-2">
        <div
          v-for="[label, value, id] in [
            ['Generation time', sample.generation_time, 'generation'],
            ['Receipt time', sample.receipt_time, 'receipt'],
          ]"
          :key="id"
          class="min-w-0"
        >
          <dt class="mb-1 text-xs text-base-content/60">{{ label }}</dt>
          <dd>
            <time
              v-if="value"
              :id="`exploration-sample-${id}`"
              :datetime="value"
              class="break-all font-mono text-xs"
              >{{ value }}</time
            >
            <span v-else class="text-sm text-base-content/60">Not recorded</span>
          </dd>
        </div>
      </dl>
      <div class="grid gap-3 md:grid-cols-2">
        <div
          v-for="[label, key] in [
            ['Raw value', 'raw_value'],
            ['Engineering value', 'engineering_value'],
          ] as const"
          :key="key"
          class="min-w-0 rounded border border-base-300 bg-base-100/70 p-3"
        >
          <h3 class="mb-2 text-xs font-medium text-base-content/70">
            {{ label }}
            <span v-if="sample[key].format === 'hex'" class="ml-1 font-mono text-base-content/50"
              >(hex)</span
            >
          </h3>
          <pre
            :id="`exploration-sample-${key}`"
            class="max-h-44 overflow-auto whitespace-pre-wrap break-all font-mono text-sm"
            :class="sample[key].state === 'ready' ? '' : 'text-base-content/60'"
            >{{ literal(sample[key]) }}</pre>
        </div>
      </div>
      <dl class="grid gap-3 sm:grid-cols-2">
        <div class="min-w-0">
          <dt class="mb-1 text-xs text-base-content/60">Stored source</dt>
          <dd id="exploration-sample-source" class="break-all font-mono text-xs">
            {{ sample.source.data_source_id }}
          </dd>
        </div>
        <div class="min-w-0">
          <dt class="mb-1 text-xs text-base-content/60">Source binding</dt>
          <dd id="exploration-sample-binding" class="break-all font-mono text-xs">
            {{ sample.source.source_binding_id }}
          </dd>
        </div>
      </dl>
      <details class="border-t border-base-300 pt-3">
        <summary class="cursor-pointer text-xs font-medium">Record provenance</summary>
        <dl class="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <div v-for="[label, value] in references" :key="String(label)" class="min-w-0">
            <dt class="mb-1 text-xs text-base-content/60">{{ label }}</dt>
            <dd class="break-all font-mono text-xs">{{ value ?? "Not recorded" }}</dd>
          </div>
          <div>
            <dt class="mb-1 text-xs text-base-content/60">Recorded revision state</dt>
            <dd id="exploration-sample-validity" class="text-xs">
              {{ sample.record.validity_state ?? "Not recorded" }}
            </dd>
          </div>
        </dl>
        <p class="mt-3 text-xs text-base-content/60">
          Recorded state reflects storage provenance, not a current canonical-status check.
        </p>
      </details>
    </div>
    <p v-else id="exploration-sample-state" role="status" class="p-4 text-sm text-base-content/70">
      {{ messages[inspection.status as keyof typeof messages] }}
    </p>
  </aside>
</template>
