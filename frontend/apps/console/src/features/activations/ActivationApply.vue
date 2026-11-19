<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import {
  decidedLine,
  notApplied,
  resume,
  resumeFailure,
  type ActivationDetail,
  type DetailKey,
} from "./api.ts";

/** U41: an approved activation that didn't apply: why, since when, and Retry apply or the next step. */
const props = defineProps<{ requestKey: DetailKey; request: ActivationDetail }>();
const emit = defineEmits<{
  resumed: [note: { tone: "nominal" | "caution"; text: string }];
  refused: [];
}>();
const line = computed(() => notApplied(props.request));
const mayRetry = computed(
  () => props.request.permissions?.includes("activations.approve") ?? false,
);
const busy = ref(false);
const failure = ref<string | null>(null);
async function retry() {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const r = await resume(props.requestKey);
    if (r.ok) emit("resumed", decidedLine("approve", r.value));
    else {
      failure.value = resumeFailure(r.error);
      emit("refused"); // ux: refetch either way, so a not_resumable row flips to not retryable
    }
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <template v-if="line">
    <ApCallout tone="caution">
      {{ line.text }}
      <template v-if="line.retry && mayRetry" #action>
        <ApButton size="compact" :disabled="busy" disabled-reason="Retrying…" @click="retry"
          >Retry apply</ApButton
        >
      </template>
    </ApCallout>
    <p v-if="line.next" class="m-0 text-md text-text-2">{{ line.next }}</p>
    <p v-else-if="line.retry && !mayRetry" class="m-0 text-md text-text-2">
      Someone who can approve activations can retry it.
    </p>
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
  </template>
</template>
