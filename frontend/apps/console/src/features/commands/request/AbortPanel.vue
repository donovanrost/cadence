<script setup lang="ts">
import { ref, shallowRef } from "vue";
import { describeApiError } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApButton, ApCallout, ApInlineConfirm, ApTextarea } from "@/ui";
import { abortGroup, type Group } from "../groups/show.ts";

/**
 * Abort remaining (M20, DECISIONS #31): cancels every uplink that hasn't started to radiate;
 * started ones keep running. Reason required, audited. U20 outcomes.
 */
const props = defineProps<{ group: Group }>();
const emit = defineEmits<{ done: [] }>();
const scope = useMissionScope();
/**
 * The kit's in-place confirm (design-language §7, fe-ops' OK): it opens on 'Why abort' (the
 * field, A1), 'Keep running' and Esc return focus to 'Abort remaining', and one is open at a time.
 * The outcome stays outside it as before: a refusal is a crit callout (role=alert).
 */
const open = ref(false);
const reason = ref("");
const busy = ref(false);
/** `failed` (a11y B6, ux #414): refused or unclear is an alert; aborted a status. */
const outcome = shallowRef<{
  tone: "crit" | "caution" | "nominal";
  text: string;
  failed: boolean;
} | null>(null);

async function run() {
  busy.value = true;
  outcome.value = null;
  try {
    const r = await abortGroup(scope.value.mission.id, props.group.id, reason.value.trim());
    if (r.status === "done") {
      const res = r.value.events.find((e) => e.kind === "aborted")?.payload;
      outcome.value = {
        tone: "nominal",
        failed: false,
        text: `Aborted: ${res?.canceled ?? 0} canceled, ${res?.already_started?.length ?? 0} already started and still running.`,
      };
      open.value = false;
      emit("done");
    } else if (r.status === "rejected")
      outcome.value = {
        tone: "crit",
        failed: true,
        text: `Not aborted. Nothing changed: ${describeApiError(r.error)}`,
      };
    else
      outcome.value = {
        tone: "caution",
        failed: true,
        text: `It's unclear whether the abort went through (${describeApiError(r.error)}). Reload before trying again.`,
      };
  } finally {
    busy.value = false;
  }
}
const onAbort = () => run().catch((e: unknown) => console.error("Abort failed", e));
</script>

<template>
  <div class="flex flex-col gap-2">
    <!-- a11y B6 (#243): aborted is a status; refused or unclear is an alert. -->
    <ApCallout v-if="outcome" :tone="outcome.tone" :role="outcome.failed ? 'alert' : 'status'">{{
      outcome.text
    }}</ApCallout>
    <ApInlineConfirm
      v-model:open="open"
      action="Abort remaining uplinks"
      cancel-label="Keep running"
      :busy="busy"
      busy-reason="Aborting…"
      :blocked="reason.trim() ? null : 'Write why first.'"
      @confirm="onAbort"
    >
      <template #trigger="{ attrs }">
        <ApButton variant="danger" size="compact" class="self-start" v-bind="attrs"
          >Abort remaining</ApButton
        >
      </template>
      Abort the uplinks that haven't started? They're canceled; ones already radiating keep running.
      <template #fields>
        <ApTextarea v-model="reason" label="Why abort" :rows="2" required />
      </template>
    </ApInlineConfirm>
  </div>
</template>
