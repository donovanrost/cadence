<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import { useCommandAccess } from "@/features/commands/index.ts";
import {
  jobEvidence,
  jobMeta,
  jobOffers,
  jobTechnical,
  jobTitle,
  JobSheets,
  NO_ACCESS_JOB,
  type Attention,
} from "@/features/now/index.ts";

/**
 * U54 pass block (job_outcome_unknown): a job tied to this pass was cut off, so its outcome is
 * unknown. Same sentences as Now, with the title minus the spacecraft and pass label, and the two
 * decisions (operators only). The job's ids live in Technical details.
 */
const props = defineProps<{ missionId: MissionId; attention: Attention; now: Date }>();
defineEmits<{ changed: [] }>();

const access = useCommandAccess();
const canRetry = computed(() => jobOffers(props.attention, "retry"));
const canClose = computed(() => jobOffers(props.attention, "close"));
const title = computed(() =>
  jobTitle(
    { ...props.attention, station: null, reservation_id: null, contact_label: null },
    null,
    props.now,
  ),
);
const sheets = ref<InstanceType<typeof JobSheets> | null>(null);
</script>

<template>
  <ApCallout tone="caution">
    <p class="m-0 font-semibold">{{ title }}</p>
    <p class="m-0 text-text-2">{{ jobEvidence(attention, now) }}</p>
    <p v-if="jobMeta(attention, now)" class="m-0 font-mono text-xs text-text-3">
      {{ jobMeta(attention, now) }}
    </p>
    <p v-if="(canRetry || canClose) && !access.abort" class="m-0 text-sm text-text-3">
      {{ NO_ACCESS_JOB }}
    </p>
    <!-- ux U54: the job's ids live here only. -->
    <details class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-for="line in jobTechnical(attention)" :key="line" class="m-0 pt-1 font-mono break-all">
        {{ line }}
      </p>
    </details>
    <template v-if="(canRetry || canClose) && access.abort" #action>
      <span class="flex flex-wrap gap-2">
        <ApButton v-if="canRetry" size="compact" @click="sheets?.openRetry(attention)"
          >Retry…</ApButton
        >
        <ApButton v-if="canClose" size="compact" @click="sheets?.openClose(attention)"
          >Close without retry…</ApButton
        >
      </span>
    </template>
  </ApCallout>
  <JobSheets ref="sheets" :mission-id="missionId" @done="$emit('changed')" />
</template>
