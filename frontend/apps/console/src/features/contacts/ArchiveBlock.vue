<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import { useCommandAccess } from "@/features/commands/index.ts";
import {
  archiveEvidence,
  archiveMeta,
  archiveOffers,
  archiveTitle,
  DiscardSheet,
  NO_ACCESS_ARCHIVE,
  retryTargets,
  serverKey,
  type Attention,
} from "@/features/now/index.ts";

/**
 * U49 pass block (archive_quarantine): raw records from this pass the archive couldn't take; their
 * telemetry was still stored. Same title and sentences as Now, with Retry and Discard… (operators
 * only). The error, its code and the id show only in Technical details.
 */
const props = defineProps<{ missionId: MissionId; attention: Attention; now: Date }>();
const emit = defineEmits<{ changed: [] }>();

const access = useCommandAccess();
const canRetry = computed(() => archiveOffers(props.attention, "retry"));
const canDiscard = computed(() => archiveOffers(props.attention, "discard"));
/** The block sits on the pass, so the title drops the spacecraft and the pass label. */
const title = computed(() => {
  const a = props.attention;
  return archiveTitle(
    { ...a, station: null, reservation_id: null, contact_label: null },
    null,
    props.now,
  );
});
const technical = computed(() => {
  const a = props.attention;
  return [
    a.error_code ? `error_code: ${serverKey(a.error_code)}` : null,
    a.error ? `error: ${a.error}` : null,
    `id: ${a.id}`,
  ].filter((l): l is string => l !== null);
});

const busy = ref(false);
const note = ref<string | null>(null);
async function retry() {
  if (busy.value) return;
  busy.value = true;
  note.value = null;
  try {
    const outcome = await retryTargets(props.missionId, [props.attention]);
    note.value = outcome.text;
    emit("changed");
  } finally {
    busy.value = false;
  }
}
const sheet = ref<InstanceType<typeof DiscardSheet> | null>(null);
</script>

<template>
  <ApCallout tone="caution">
    <p class="m-0 font-semibold">{{ title }}</p>
    <p class="m-0 text-text-2">{{ busy ? "Retrying…" : archiveEvidence(attention) }}</p>
    <p v-if="archiveMeta(attention, now)" class="m-0 font-mono text-xs text-text-3">
      {{ archiveMeta(attention, now) }}
    </p>
    <p v-if="(canRetry || canDiscard) && !access.abort" class="m-0 text-sm text-text-3">
      {{ NO_ACCESS_ARCHIVE }}
    </p>
    <p v-if="note" class="m-0 text-sm text-caution-text">{{ note }}</p>
    <!-- ux U49: the error, its code and the id live here only, never in the copy. -->
    <details class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-for="line in technical" :key="line" class="m-0 pt-1 font-mono break-all">{{ line }}</p>
    </details>
    <template v-if="(canRetry || canDiscard) && access.abort" #action>
      <span class="flex flex-wrap gap-2">
        <ApButton v-if="canRetry" size="compact" :disabled="busy" @click="retry">Retry</ApButton>
        <ApButton
          v-if="canDiscard"
          size="compact"
          variant="danger"
          :disabled="busy"
          @click="sheet?.open(attention)"
          >Discard…</ApButton
        >
      </span>
    </template>
  </ApCallout>
  <DiscardSheet ref="sheet" :mission-id="missionId" @done="$emit('changed')" />
</template>
