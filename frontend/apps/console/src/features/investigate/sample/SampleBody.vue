<script setup lang="ts">
import { computed } from "vue";
import { describeApiError, type RemoteState } from "@/api/index.ts";
import { ApButton } from "@/ui";
import type { SampleRead } from "./api.ts";
import { cautionRow, sampleRows, statusView, technicalRows } from "./words.ts";

/** ux U80: the Sample aside's body, the same in the T1 column and in the sheet below 1100px. */
const props = defineProps<{
  state: RemoteState<SampleRead>;
  /** `02:08:11Z`, the time the link rang (for ambiguous). */
  atLabel: string | null;
  today: string;
}>();
defineEmits<{ retry: []; showAt: [] }>();
const read = computed(() => (props.state.status === "ready" ? props.state.value : null));
const status = computed(() => (read.value ? statusView(read.value.status, props.atLabel) : null));
const sample = computed(() => (read.value?.status === "ready" ? read.value.sample : null));
const rows = computed(() => (sample.value ? sampleRows(sample.value, props.today) : []));
const technical = computed(() => (sample.value ? technicalRows(sample.value) : []));
</script>

<template>
  <div class="flex flex-col gap-3 p-4">
    <p v-if="state.status === 'loading'" role="status" class="m-0 font-mono text-sm text-text-4">
      LOADING SAMPLE…
    </p>
    <template v-else-if="state.status === 'failed'">
      <p class="m-0 text-sm text-caution-text">
        Couldn't read the sample: {{ describeApiError(state.error) }}
      </p>
      <ApButton size="compact" variant="secondary" class="self-start" @click="$emit('retry')"
        >Try again</ApButton
      >
    </template>
    <template v-else-if="status">
      <p class="m-0 text-sm text-text-2">{{ status.line }}</p>
      <ApButton
        v-if="status.action === 'retry'"
        size="compact"
        variant="secondary"
        class="self-start"
        @click="$emit('retry')"
        >Try again</ApButton
      >
      <ApButton
        v-else-if="status.action === 'show-at'"
        size="compact"
        variant="secondary"
        class="self-start"
        @click="$emit('showAt')"
        >Show {{ atLabel }} on the plot</ApButton
      >
    </template>
    <template v-else-if="sample">
      <dl class="m-0 grid grid-cols-[max-content_minmax(0,1fr)] gap-x-4 gap-y-2 text-sm">
        <template v-for="r in rows" :key="r.key">
          <dt class="ap-label">{{ r.label }}</dt>
          <dd
            class="m-0 break-all"
            :class="[
              r.mono ? 'font-mono' : '',
              cautionRow(r) ? 'text-caution-text' : 'text-text-2',
            ]"
          >
            {{ r.value }}
          </dd>
        </template>
      </dl>
      <details class="text-xs text-text-3">
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <dl class="m-0 flex flex-col gap-1 pt-2">
          <div v-for="r in technical" :key="r.key" class="flex min-w-0 flex-col">
            <dt class="text-text-4">{{ r.label }}</dt>
            <dd class="m-0 font-mono break-all whitespace-pre-wrap text-text-2">{{ r.value }}</dd>
          </div>
        </dl>
      </details>
    </template>
  </div>
</template>
