<script setup lang="ts">
import { computed } from "vue";
import { ApTag } from "@/ui";
import { overlapTechnical, overlapWords, type ListenerOverlap } from "./listenerOverlap.ts";

/**
 * U58 (b), #361: the LISTENER OVERLAP tag and its sentence on a pass that may lose its start, or
 * the earlier pass's muted note. The listener's port stays in Technical details (U58).
 */
const props = defineProps<{ overlap: ListenerOverlap | null | undefined }>();
const view = computed(() => overlapWords(props.overlap));
const technical = computed(() => (view.value ? overlapTechnical(props.overlap) : null));
</script>

<template>
  <div v-if="view" class="flex flex-col gap-1" data-listener-overlap>
    <p v-if="view.tag" class="m-0 flex flex-wrap items-start gap-2 text-sm text-readout">
      <ApTag state="caution" label="Listener overlap" />
      <span>{{ view.text }}</span>
    </p>
    <p v-else class="m-0 text-sm text-text-3">{{ view.text }}</p>
    <details v-if="technical" class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p class="m-0 pt-1 font-mono break-all">{{ technical }}</p>
    </details>
  </div>
</template>
