<script setup lang="ts">
import { ApButton } from "@/ui";

/**
 * U65 decision: Approve rev N (primary; the panel is its confirm) and Reject… (a confirm with a
 * reason). With no report yet, Run comparison leads and Approve waits for it.
 */
defineProps<{
  revWord: string;
  reportId: string | null;
  busy: "run" | "approve" | "reject" | null;
}>();
defineEmits<{ run: []; approve: [reportId: string]; reject: [] }>();
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <ApButton
      v-if="reportId === null"
      data-approval-run
      variant="primary"
      :disabled="busy !== null"
      disabled-reason="Comparing…"
      @click="$emit('run')"
      >Run comparison</ApButton
    >
    <ApButton
      data-approval-approve
      :variant="reportId === null ? 'secondary' : 'primary'"
      :disabled="reportId === null || busy !== null"
      :disabled-reason="reportId === null ? 'Run the comparison first.' : 'Approving…'"
      @click="reportId && $emit('approve', reportId)"
      >Approve {{ revWord }}</ApButton
    >
    <ApButton :disabled="busy !== null" disabled-reason="Working…" @click="$emit('reject')"
      >Reject…</ApButton
    >
  </div>
</template>
