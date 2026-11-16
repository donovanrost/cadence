<script setup lang="ts">
import { nextTick, ref, shallowRef } from "vue";
import { describeApiError } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApButton, ApCallout, ApTextarea } from "@/ui";
import { abortGroup, type Group } from "../groups/show.ts";

/**
 * Abort remaining (M20, DECISIONS #31): cancels every uplink that hasn't started to radiate;
 * started ones keep running. Reason required, audited. U20 outcomes.
 */
const props = defineProps<{ group: Group }>();
const emit = defineEmits<{ done: [] }>();
const scope = useMissionScope();
const open = ref(false);
const root = ref<HTMLElement | null>(null);
/**
 * a11y (ux A1/A5 for an inline confirm): the button that opens or closes it disappears, so focus
 * would fall to <body>. Opening lands on the safe 'Keep running'; Keep running returns to
 * 'Abort remaining'.
 */
async function setOpen(value: boolean) {
  open.value = value;
  await nextTick();
  root.value
    ?.querySelector<HTMLElement>(value ? "[data-focus=keep]" : "[data-focus=abort]")
    ?.focus();
}
const reason = ref("");
const busy = ref(false);
const outcome = shallowRef<{ tone: "crit" | "caution" | "nominal"; text: string } | null>(null);

async function run() {
  busy.value = true;
  outcome.value = null;
  try {
    const r = await abortGroup(scope.value.mission.id, props.group.id, reason.value.trim());
    if (r.status === "done") {
      const res = r.value.events.find((e) => e.kind === "aborted")?.payload;
      outcome.value = {
        tone: "nominal",
        text: `Aborted: ${res?.canceled ?? 0} canceled, ${res?.already_started?.length ?? 0} already started and still running.`,
      };
      open.value = false;
      emit("done");
    } else if (r.status === "rejected")
      outcome.value = {
        tone: "crit",
        text: `Not aborted. Nothing changed: ${describeApiError(r.error)}`,
      };
    else
      outcome.value = {
        tone: "caution",
        text: `It's unclear whether the abort went through (${describeApiError(r.error)}). Reload before trying again.`,
      };
  } finally {
    busy.value = false;
  }
}
const onAbort = () => run().catch((e: unknown) => console.error("Abort failed", e));
</script>

<template>
  <div ref="root" class="flex flex-col gap-2">
    <ApCallout v-if="outcome" :tone="outcome.tone">{{ outcome.text }}</ApCallout>
    <ApButton v-if="!open" variant="danger" size="compact" data-focus="abort" @click="setOpen(true)"
      >Abort remaining</ApButton
    >
    <div v-else class="flex flex-col gap-2">
      <ApTextarea
        v-model="reason"
        label="Why abort"
        :rows="2"
        required
        hint="Uplinks already radiating keep running."
      />
      <div class="flex gap-2">
        <ApButton
          variant="danger"
          size="compact"
          :disabled="!reason.trim() || busy"
          :disabled-reason="busy ? 'Aborting…' : 'Write why first.'"
          @click="onAbort"
          >Abort remaining uplinks</ApButton
        >
        <ApButton size="compact" variant="ghost" data-focus="keep" @click="setOpen(false)"
          >Keep running</ApButton
        >
      </div>
    </div>
  </div>
</template>
