<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, onBeforeUnmount, ref } from "vue";
import { describeApiError, isError } from "@/api/index.ts";
import { ApButton, ApSheet, ApTextarea } from "@/ui";
import type { Attention } from "./attention.ts";
import {
  STUCK_TODO,
  bufferLine,
  stuckAckLine,
  stuckTitle,
  stuckWhy,
  whatStopped,
} from "./stuckProcessing.ts";
import { keepWhole } from "./queue.ts";
import {
  NOTE_MAX,
  NO_ACCESS_STUCK,
  acknowledgeStuck,
  craftNames,
  stuckOpen,
  stuckTechnical,
} from "./stuckRow.ts";

/**
 * ux U84: the Stuck processing sheet, opened by the row's `Acknowledge…` or `Details`. What
 * stopped, why, the buffer, what to do, who was told; Copy details; Technical details; then the
 * note and Acknowledge for operators while the item is open.
 */
const props = defineProps<{
  missionId: MissionId;
  canAck: boolean;
  /** a11y A5 (#243): where focus goes when the row (the opener) resolved and is gone. */
  returnFocus?: (() => HTMLElement | null) | undefined;
}>();
const emit = defineEmits<{ done: [item: Attention | null] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const target = ref<Attention | null>(null);
const note = ref("");
const error = ref<string | null>(null);
const busy = ref(false);
const copied = ref("");
let copiedTimer: ReturnType<typeof setTimeout> | undefined;
onBeforeUnmount(() => clearTimeout(copiedTimer));

const now = () => new Date();
const lines = computed(() => {
  const a = target.value;
  if (!a) return [];
  return [whatStopped(a), stuckWhy(a, now()), bufferLine(a, now()), STUCK_TODO].filter(
    (l): l is string => l !== null,
  );
});
/** ux U84: craft names stay whole when a line wraps. */
const names = computed(() => (target.value ? craftNames(target.value) : []));
const ack = computed(() => (target.value ? stuckAckLine(target.value, now()) : null));
const technical = computed(() => (target.value ? stuckTechnical(target.value) : []));
const acking = computed(() => props.canAck && target.value !== null && stuckOpen(target.value));

function open(a: Attention) {
  target.value = a;
  note.value = "";
  error.value = null;
  copied.value = "";
  sheet.value?.open();
}

/** Copy details: the Technical details as plain text; "Copied" for 2 s (U84). */
async function copy() {
  try {
    await navigator.clipboard.writeText(technical.value.join("\n"));
    copied.value = "Copied";
  } catch {
    copied.value = "Couldn't copy. Select the Technical details instead.";
  }
  clearTimeout(copiedTimer);
  copiedTimer = setTimeout(() => (copied.value = ""), 2_000);
}

async function acknowledge() {
  const a = target.value;
  if (!a || busy.value) return;
  busy.value = true;
  error.value = null;
  try {
    const r = await acknowledgeStuck(props.missionId, a, note.value);
    if (r.ok) {
      sheet.value?.close();
      emit("done", r.value);
    } else if (r.error.kind === "not_found") {
      // It closed meanwhile (the fix landed): the next read shows it resolved.
      sheet.value?.close();
      emit("done", null);
    } else if (r.error.kind === "forbidden") error.value = NO_ACCESS_STUCK;
    else if (isError(r.error, "invalid_note"))
      error.value = `Keep the note to ${NOTE_MAX} characters.`;
    else error.value = describeApiError(r.error);
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <!-- a11y A1: acknowledging opens on its Note (the first field); Details opens on Close. -->
  <ApSheet
    ref="sheet"
    :title="target ? stuckTitle(target, now()) : 'Stuck processing'"
    :initial-focus="acking ? 'textarea' : 'footer button'"
    :return-focus="returnFocus"
  >
    <p class="ap-label m-0">Stuck processing</p>
    <p v-for="(line, i) in lines" :key="i" class="m-0 text-md text-text-2">
      <template v-for="(part, n) in keepWhole(line, names)" :key="n">
        <span v-if="typeof part !== 'string'" class="whitespace-nowrap">{{ part.text }}</span>
        <template v-else>{{ part }}</template>
      </template>
    </p>
    <p v-if="ack" class="m-0 text-md text-text-2">{{ ack }}</p>
    <div class="flex items-center gap-3">
      <ApButton size="compact" variant="ghost" @click="copy">Copy details</ApButton>
      <span class="text-sm text-text-3" role="status">{{ copied }}</span>
    </div>
    <details class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-for="t in technical" :key="t" class="m-0 font-mono break-all">{{ t }}</p>
    </details>
    <ApTextarea
      v-if="acking"
      v-model="note"
      label="Note"
      placeholder="Who you told, e.g. domain at 03:18Z"
      :maxlength="NOTE_MAX"
    />
    <p v-else-if="target && stuckOpen(target)" class="m-0 text-sm text-text-3">
      {{ NO_ACCESS_STUCK }}
    </p>
    <p v-if="error" role="alert" class="m-0 text-sm text-crit-text">{{ error }}</p>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">{{ acking ? "Cancel" : "Close" }}</ApButton>
      <ApButton
        v-if="acking"
        variant="primary"
        :disabled="busy"
        disabled-reason="Acknowledging…"
        @click="acknowledge"
        >Acknowledge</ApButton
      >
    </template>
  </ApSheet>
</template>
