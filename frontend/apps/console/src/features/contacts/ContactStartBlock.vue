<script setup lang="ts">
import type { MissionId, SpacecraftId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";
import { plural, ApButton, ApCallout } from "@/ui";
import { useCommandAccess } from "@/features/commands/index.ts";
import {
  holderPass,
  NO_ACCESS_MISSED,
  seenTargets,
  serverKey,
  short,
  startEvidence,
  startReasonAction,
  type Attention,
} from "@/features/now/index.ts";

/**
 * U45 pass block (contact_start): this pass failed to start. While it's on, Cadence retries by
 * itself; once missed, Mark as seen closes it (operate_mission, as U37). The holder pass links;
 * the reason key and the raw error live in Technical details only.
 */
const props = defineProps<{
  missionId: MissionId;
  attention: Attention;
  now: Date;
  /** The pass's craft: transport_archived's Book a pass books for it (ux U45). */
  spacecraftId?: SpacecraftId | null | undefined;
}>();
const emit = defineEmits<{ changed: [] }>();

const access = useCommandAccess();
const missed = computed(() => props.attention.conflict === "missed");
const holder = computed((): { label: string; to: RouteLocationRaw } | null => {
  const h = props.attention.holder;
  const pass = h ? (h.reservation_id ?? h.contact_id) : null;
  return h && pass
    ? {
        label: `Open the ${holderPass(h, props.now)}`,
        to: { name: "ops.contacts", query: { contact: pass } },
      }
    : null;
});
const fix = computed(() => startReasonAction(props.attention, props.spacecraftId ?? null));
/** "Cadence is retrying · 3 tries · last at 03:12Z"; nothing once missed. */
const tries = computed(() => {
  const a = props.attention;
  if (missed.value) return null;
  return [
    "Cadence is retrying",
    a.attempts != null ? plural(a.attempts, "try", "tries") : null,
    a.last_attempt_at ? `last at ${short(a.last_attempt_at, props.now)}` : null,
  ]
    .filter(Boolean)
    .join(" · ");
});
const reasonKey = computed(() => {
  const r = props.attention.reason;
  return r == null ? null : serverKey(r);
});

const busy = ref(false);
const note = ref<string | null>(null);
async function markSeen() {
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
  <ApCallout :tone="missed ? 'crit' : 'caution'">
    <p class="m-0 font-semibold">
      {{ missed ? "This pass was missed." : "This pass hasn't started." }}
    </p>
    <p class="m-0 text-text-2">{{ busy ? "Marking…" : startEvidence(attention, now) }}</p>
    <p v-if="tries" class="m-0 text-sm text-text-3">{{ tries }}</p>
    <p v-if="holder || fix" class="m-0 flex flex-wrap gap-3 text-sm">
      <RouterLink
        v-if="holder"
        :to="holder.to"
        class="max-md:hit-44 text-readout underline hover:text-bright"
        >{{ holder.label }}</RouterLink
      >
      <RouterLink
        v-if="fix"
        :to="fix.to"
        class="max-md:hit-44 text-readout underline hover:text-bright"
        >{{ fix.label }}</RouterLink
      >
    </p>
    <p v-if="missed && !access.abort" class="m-0 text-sm text-text-3">{{ NO_ACCESS_MISSED }}</p>
    <p v-if="note" class="m-0 text-sm text-caution-text">{{ note }}</p>
    <!-- ux U45: the key and the raw error live here only, never in the copy. -->
    <details v-if="reasonKey || attention.failure_message" class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-if="reasonKey" class="m-0 pt-1 font-mono">reason: {{ reasonKey }}</p>
      <p v-if="attention.failure_message" class="m-0 font-mono break-all">
        {{ attention.failure_message }}
      </p>
    </details>
    <template v-if="missed && access.abort" #action>
      <ApButton size="compact" :disabled="busy" @click="markSeen">Mark as seen</ApButton>
    </template>
  </ApCallout>
</template>
