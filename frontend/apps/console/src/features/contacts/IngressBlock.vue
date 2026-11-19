<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { plural, ApButton, ApCallout } from "@/ui";
import { useCommandAccess } from "@/features/commands/index.ts";
import {
  ingressEvidence,
  ingressMeta,
  NO_ACCESS_ACK_LOST,
  seenTargets,
  serverKey,
  size,
  type Attention,
} from "@/features/now/index.ts";

/**
 * U47 pass block (ingress_backpressure): this pass's telemetry backing up in Cadence's buffer, or
 * frames lost when it was full. Same sentences as Now; lost frames are acknowledged here too
 * (operate_mission). The journal, stream and raw error show only in Technical details.
 */
const props = defineProps<{ missionId: MissionId; attention: Attention }>();
const emit = defineEmits<{ changed: [] }>();

const access = useCommandAccess();
const lost = computed(() => props.attention.conflict === "frames_dropped");
const acknowledged = computed(() => props.attention.state === "acknowledged");
const title = computed(() => {
  const d = props.attention.drops;
  return lost.value && d
    ? `${plural(d.count, "telemetry frame", "telemetry frames")} lost.`
    : "Telemetry is backing up.";
});
const canAck = computed(() => lost.value && !acknowledged.value);
const technical = computed(() => {
  const a = props.attention;
  const u = a.journal_usage;
  const d = a.drops;
  return [
    u
      ? `journal: ${size(u.used_bytes)} of ${size(u.capacity_bytes)} (${(u.ratio * 100).toFixed(1)}%, threshold ${Math.round(u.threshold * 100)}%), ${size(u.backlog_bytes)} not persisted`
      : null,
    d ? `dropped from: ${serverKey(d.buffer)} buffer` : null,
    a.transport
      ? `transport: ${serverKey(a.transport.kind)} · ${a.transport.provider_binding_id}`
      : null,
    a.diagnostics?.stream_id ? `stream: ${a.diagnostics.stream_id}` : null,
    a.diagnostics?.last_error ? `error: ${a.diagnostics.last_error}` : null,
  ].filter((l): l is string => l !== null);
});

const busy = ref(false);
const note = ref<string | null>(null);
async function acknowledge() {
  if (busy.value) return;
  busy.value = true;
  note.value = null;
  try {
    const outcome = await seenTargets(props.missionId, [props.attention]);
    note.value = outcome.text;
    if (!outcome.text) emit("changed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApCallout :tone="lost ? 'crit' : 'caution'">
    <p class="m-0 font-semibold">{{ title }}</p>
    <p class="m-0 text-text-2">{{ busy ? "Acknowledging…" : ingressEvidence(attention) }}</p>
    <p v-if="ingressMeta(attention)" class="m-0 font-mono text-xs text-text-3">
      {{ ingressMeta(attention) }}
    </p>
    <p v-if="canAck && !access.abort" class="m-0 text-sm text-text-3">{{ NO_ACCESS_ACK_LOST }}</p>
    <p v-if="note" class="m-0 text-sm text-caution-text">{{ note }}</p>
    <!-- ux U47: the journal, stream and raw error live here only, never in the copy. -->
    <details v-if="technical.length" class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-for="line in technical" :key="line" class="m-0 pt-1 font-mono break-all">{{ line }}</p>
    </details>
    <template v-if="canAck && access.abort" #action>
      <ApButton size="compact" :disabled="busy" @click="acknowledge">Acknowledge</ApButton>
    </template>
  </ApCallout>
</template>
