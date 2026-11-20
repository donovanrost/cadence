<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref, useId } from "vue";
import { ApButton, ApSheet } from "@/ui";
import GrantRefusal from "./GrantRefusal.vue";
import { resumedLine, resumeFailure, resumeLine } from "./grant-suspended.ts";
import type { Worded } from "./grant-words.ts";
import { operationIds, resumeGrant, type Grant } from "./grants.ts";

/**
 * U105 Resume… (#499): a suspended grant takes effect again, at the hash read, with an
 * operation_id a retry of the same request reuses (#257), so a replay answers as this one. Who may
 * resume is the server's (A6); after a separation refusal Resume stays off with its line.
 */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ resumed: [said: string] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
// ux a11y A1: focus starts on Cancel, so the line describes the dialog.
const line = useId();
const grant = ref<Grant | null>(null);
const busy = ref(false);
const failure = ref<Worded | null>(null);
const disabled = ref<Worded | null>(null);
const ops = operationIds();
/**
 * ca-engineer on #565: a separation refusal holds for the grant as it was read, so reopening the
 * sheet keeps Resume disabled until the grant changes (a new sha256 after a reload).
 */
const held = new Map<string, Worded>();
const keyOf = (g: Grant) => `${g.id}:${g.sha256}`;
function open(g: Grant) {
  grant.value = g;
  failure.value = null;
  disabled.value = held.get(keyOf(g)) ?? null;
  sheet.value?.open();
}
async function submit() {
  const g = grant.value;
  if (!g || busy.value || disabled.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const r = await resumeGrant(props.missionId, g, ops(`resume:${g.id}:${g.sha256}`));
    if (r.ok) {
      sheet.value?.close();
      return void emit("resumed", resumedLine(r.value.grant));
    }
    const f = resumeFailure(r.error, g);
    failure.value = f;
    if (f.disable) {
      disabled.value = f.disable;
      held.set(keyOf(g), f.disable);
    }
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Resume the grant" width="narrow" :described-by="line">
    <div class="flex flex-col gap-3">
      <p :id="line" class="m-0 text-md text-text-3">{{ grant ? resumeLine(grant) : "" }}</p>
      <GrantRefusal :refusal="failure" />
    </div>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        data-grant-resume
        variant="primary"
        :disabled="busy || disabled !== null"
        :disabled-reason="disabled?.text ?? 'Resuming…'"
        @click="submit"
        >Resume</ApButton
      >
    </template>
  </ApSheet>
</template>
