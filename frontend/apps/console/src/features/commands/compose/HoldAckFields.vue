<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApCallout, ApTextarea } from "@/ui";
import { checkKeyText, HOLD_NOTE_MAX, type PreflightCheck } from "../groups/api.ts";
import { checkLabel, type HoldAcks } from "../groups/checks.ts";
import { holdPlaceholder } from "../groups/withdrawn.ts";
import { heldCount } from "../groups/withdrawnSentence.ts";

/**
 * #60/#61: a note per ackable HOLD, stamped with the hold_basis it was written against. If the HOLD
 * changes after that (new basis), the note stops counting until the operator re-confirms it.
 * Used by Compose (C3) and by Approve for HOLDs the author's acks don't cover.
 */
const props = defineProps<{ holds: readonly PreflightCheck[]; acks: HoldAcks; hint: string }>();
defineEmits<{ ack: [key: string, basis: string | null, note: string] }>();
/** One field per HOLD, keyed by its check key as text (what an ack sends back). */
const rows = computed(() =>
  props.holds.map((c) => ({
    key: checkKeyText(c.key),
    label: checkLabel(c.key),
    basis: c.hold_basis ?? null,
    // U109: the Composition HOLD's note asks why it's safe to command the held targets.
    placeholder: c.key === "model_approval_withdrawn" ? holdPlaceholder(heldCount(c)) : undefined,
  })),
);
const stale = (key: string, basis: string | null) => {
  const a = props.acks[key];
  return a !== undefined && a.note.trim() !== "" && a.basis !== basis;
};
</script>

<template>
  <div
    v-for="c in rows"
    :key="c.key"
    class="flex flex-col gap-2 border-t border-hairline px-4 py-3"
  >
    <ApTextarea
      :model-value="acks[c.key]?.note ?? ''"
      :label="`Acknowledge the ${c.label} HOLD`"
      :hint="hint"
      :placeholder="c.placeholder"
      :maxlength="HOLD_NOTE_MAX"
      :rows="2"
      @update:model-value="(note: string) => $emit('ack', c.key, c.basis, note)"
    />
    <ApCallout v-if="stale(c.key, c.basis)" tone="caution">
      This HOLD changed after you acknowledged it. Read it again.
      <template #action
        ><ApButton size="compact" @click="$emit('ack', c.key, c.basis, acks[c.key]?.note ?? '')"
          >Still acknowledge</ApButton
        ></template
      >
    </ApCallout>
  </div>
</template>
