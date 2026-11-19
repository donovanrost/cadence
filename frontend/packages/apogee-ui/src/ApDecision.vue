<script setup lang="ts" generic="Value extends string">
import { computed, ref } from "vue";
import ApButton from "./ApButton.vue";
import ApOption from "./ApOption.vue";
import ApTextarea from "./ApTextarea.vue";
import { fieldId } from "./field-id.ts";

/**
 * A recorded human decision (two-person GO, change-set approval): radio options, a note that some
 * options require, an optional log, and one commit-size primary. The commit label follows the
 * chosen option. Server authority stays with the caller: `commit` only reports the choice.
 */
export type ApDecisionOption<V extends string> = Readonly<{
  value: V;
  title: string;
  description?: string | undefined;
  /** The note is required for this option (send back, NO-GO, exclusions). */
  needsNote?: boolean | undefined;
  /** Commit button text for this option, e.g. `Sign GO · 96 targets`. */
  commitLabel: string;
}>;

const props = withDefaults(
  defineProps<{
    options: readonly ApDecisionOption<Value>[];
    noteLabel: string;
    legend?: string | undefined;
    caption?: string | undefined;
    busy?: boolean | undefined;
    /** Why committing isn't possible at all (e.g. "You can't approve your own request."). */
    blockedReason?: string | null | undefined;
  }>(),
  { legend: "Decision", busy: false, blockedReason: null },
);
const emit = defineEmits<{ commit: [decision: { value: Value; note: string }] }>();
const choice = defineModel<Value | null>({ default: null });
const note = ref("");
const name = fieldId("ap-decision");

const selected = computed(() => props.options.find((o) => o.value === choice.value) ?? null);
const reason = computed(() => {
  if (props.blockedReason) return props.blockedReason;
  if (!selected.value) return "Choose a decision first.";
  if (selected.value.needsNote && note.value.trim() === "")
    return `Add a note to ${selected.value.title.toLowerCase()}.`;
  return null;
});
function commit() {
  if (reason.value === null && choice.value !== null)
    emit("commit", { value: choice.value, note: note.value.trim() });
}
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <div class="flex min-h-0 flex-1 flex-col gap-3.5 overflow-auto px-4 py-3.5">
      <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
        <legend class="ap-label mb-2.5">{{ legend }}</legend>
        <ApOption
          v-for="option in options"
          :key="option.value"
          v-model="choice"
          :value="option.value"
          :name="name"
          :title="option.title"
          :description="option.description"
        />
      </fieldset>
      <ApTextarea
        v-model="note"
        :label="noteLabel"
        :hint="selected?.needsNote ? 'Required for this decision.' : 'Optional.'"
      />
      <div v-if="$slots.log" class="border-t border-hairline pt-3"><slot name="log" /></div>
    </div>
    <div class="flex flex-none flex-col gap-2 border-t border-hairline px-4 py-3">
      <ApButton
        variant="primary"
        size="commit"
        :disabled="reason !== null || busy"
        :disabled-reason="busy ? 'Recording your decision…' : (reason ?? undefined)"
        @click="commit"
      >
        {{ selected?.commitLabel ?? "Decide" }}
      </ApButton>
      <p v-if="reason" class="m-0 text-center text-sm text-text-3">{{ reason }}</p>
      <p v-else-if="caption" class="m-0 text-center font-mono text-2xs text-text-4 uppercase">
        {{ caption }}
      </p>
    </div>
  </div>
</template>
