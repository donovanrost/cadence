<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark } from "@/ui";
import type { Pass } from "./api.ts";
import { scidMismatchIds, scidMismatchLines } from "./scidMismatch.ts";

/** ux U81 §2: unlike U67's quiet note this isn't normal, so a caution line at full contrast. */
const props = defineProps<{ mismatch: Pass["scid_mismatch"]; spacecraft: string | null }>();
const lines = computed(() => scidMismatchLines(props.mismatch, props.spacecraft));
const ids = computed(() => scidMismatchIds(props.mismatch));
</script>

<template>
  <div v-if="lines.length" class="flex flex-col gap-1">
    <p v-for="line in lines" :key="line" class="m-0 flex items-start gap-2 text-sm text-readout">
      <ApStatusMark state="caution" class="mt-1" />
      <span>{{ line }}</span>
    </p>
    <details class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-for="line in ids" :key="line" class="m-0 pt-1 font-mono break-all">{{ line }}</p>
    </details>
  </div>
</template>
