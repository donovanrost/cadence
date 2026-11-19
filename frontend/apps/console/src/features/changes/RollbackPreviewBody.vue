<script setup lang="ts">
import type { RemoteState } from "@/api";
import { ApCallout, plural } from "@/ui";
import ChecksPanel from "./ChecksPanel.vue";
import type { Preview } from "./actions.ts";
import RollbackOps from "./RollbackOps.vue";
import type { RollbackPreview } from "./rollback.ts";

/** The rollback's dry run: what it stages back, outside changes it overwrites, and its checks. */
defineProps<{
  value: RollbackPreview;
  to: number;
  /** The first NO-GO item in words, or null when nothing blocks. */
  noGoReason: string | null;
  checks: RemoteState<Preview> | null;
}>();
defineEmits<{ retry: [] }>();
</script>

<template>
  <p class="m-0 font-semibold text-readout">{{ value.summary }}</p>
  <RollbackOps :ops="value.ops" :diffs="value.preview?.diffs ?? []" />
  <ApCallout v-if="value.outside.length > 0" tone="caution">
    {{ plural(value.outside.length, "part of the configuration", "parts of the configuration") }}
    changed outside change sets since r{{ to }}. The rollback overwrites them; you'll acknowledge
    that when you submit.
  </ApCallout>
  <ApCallout v-if="value.preview === null" tone="info"
    >Nothing differs from the live revision.</ApCallout
  >
  <ApCallout v-if="noGoReason" tone="crit"
    >This rollback can't be staged: {{ noGoReason }}</ApCallout
  >
  <ChecksPanel
    v-if="checks"
    :preview="checks"
    :left-by="`r${value.head}`"
    @retry="$emit('retry')"
  />
</template>
