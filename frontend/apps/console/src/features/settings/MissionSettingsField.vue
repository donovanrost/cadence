<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { diffEdits, SchemaForm, type FormValues } from "@/features/changes/index.ts";
import { ApButton, ApInlineConfirm, ApTag, refocusFirst, useInPlaceSwap } from "@/ui";
import { fieldTag, initialValues, resetConfirm, valueText, type SettingsField } from "./api.ts";
import {
  canInherit,
  disabledValues,
  inheritHint,
  optionsHint,
  readOnly,
  readOnlyHint,
} from "./governance.ts";

/**
 * One mission setting (ux per-field overrides, the Profile P3 pattern): its value and source tag;
 * an inherited one can be overridden; one set here can change or reset to inherited.
 */
const props = defineProps<{
  field: SettingsField;
  canChange: boolean;
  busy: boolean;
  /** Governance/approval: Reset confirms first, naming the organization's value (ux). */
  confirmReset: boolean;
  orgName: string;
  missionName: string;
  /** Explain #233's limits (ux U96); off in a locked section, whose callout says why. */
  explain: boolean;
}>();
const emit = defineEmits<{
  save: [values: Readonly<Record<string, unknown>>];
  reset: [];
  unchanged: [];
}>();
const setHere = computed(() => props.field.source === "mission");
/** #233: this viewer may choose no value here (allowed_values []), so there's no Change/Override. */
const fixed = computed(() => readOnly(props.field));
const inherits = computed(() => canInherit(props.field));
const disabled = computed(() => disabledValues([props.field]));
/** ux U96's lines for what this viewer can't do, shown before any save. */
const hints = computed(() =>
  props.explain
    ? [
        editing.value ? optionsHint(props.field) : readOnlyHint(props.field),
        setHere.value && !editing.value ? inheritHint(props.field, props.missionName) : null,
      ].filter((h): h is string => h !== null)
    : [],
);
const schema = computed(() => ({ kind: "settings", fields: [props.field] }));
// a11y A1/A5: Override and Change swap in the field (focus it); Save and Cancel swap back to the
// opener. A reset or save that flips the source re-renders the buttons; land on the opener then.
const root = ref<HTMLElement | null>(null);
const edit = useInPlaceSwap(root);
const editing = edit.open;
watch(setHere, () => refocusFirst(root.value?.querySelector<HTMLElement>("[data-swap-opener]")), {
  flush: "post",
});
/** Governance's Reset confirms in place, naming the organization's value (ApInlineConfirm, §7). */
const confirming = ref(false);
function reset() {
  confirming.value = false;
  emit("reset");
}
const before = ref<FormValues>({});
const values = ref<FormValues>({});
const errors = ref<Readonly<Record<string, string>>>({});
function start() {
  before.value = initialValues({ fields: [props.field] });
  values.value = { ...before.value };
  errors.value = {};
  void edit.show();
}
function save() {
  const edits = diffEdits(schema.value, before.value, values.value);
  if (!edits.ok) return void (errors.value = edits.errors);
  if (edits.changes.length === 0) return void emit("unchanged");
  emit("save", Object.fromEntries(edits.changes.map((c) => [c.path, c.value])));
  void edit.hide();
}
</script>

<template>
  <div ref="root" class="flex flex-col gap-2 bg-panel px-4 py-3">
    <div class="flex items-start justify-between gap-3">
      <span class="ap-label">{{ field.label }}</span>
      <ApTag v-if="fieldTag(field)" state="off" :label="fieldTag(field) ?? ''" />
    </div>
    <SchemaForm
      v-if="editing"
      data-swap-editor
      v-model="values"
      :schema="schema"
      :errors="errors"
      :disabled-values="disabled"
    />
    <span v-else class="font-mono text-md" :class="setHere ? 'text-readout' : 'text-text-4'">{{
      valueText(field)
    }}</span>
    <span v-if="field.help && !editing" class="text-sm text-text-3">{{ field.help }}</span>
    <div v-if="canChange" class="flex flex-wrap gap-2">
      <template v-if="editing">
        <ApButton
          size="compact"
          variant="primary"
          :disabled="busy"
          disabled-reason="Saving…"
          @click="save"
          >Save</ApButton
        >
        <ApButton size="compact" variant="ghost" @click="edit.hide()">Cancel</ApButton>
      </template>
      <template v-else>
        <ApButton v-if="!fixed" size="compact" data-swap-opener @click="start">{{
          setHere ? "Change" : "Override"
        }}</ApButton>
        <ApInlineConfirm
          v-if="setHere && confirmReset"
          v-model:open="confirming"
          action="Reset to inherited"
          :busy="busy"
          busy-reason="Saving…"
          @confirm="reset"
        >
          <template #trigger="{ attrs }">
            <ApButton
              size="compact"
              variant="ghost"
              :disabled="busy || !inherits"
              :disabled-reason="busy ? 'Saving…' : (inheritHint(field, missionName) ?? undefined)"
              v-bind="attrs"
              >Reset to inherited…</ApButton
            >
          </template>
          {{ resetConfirm(field, orgName) }}
        </ApInlineConfirm>
        <ApButton
          v-else-if="setHere"
          size="compact"
          variant="ghost"
          :disabled="busy || !inherits"
          :disabled-reason="busy ? 'Saving…' : (inheritHint(field, missionName) ?? undefined)"
          @click="emit('reset')"
          >Reset to inherited</ApButton
        >
      </template>
    </div>
    <span v-for="h in hints" :key="h" class="text-sm text-text-3">{{ h }}</span>
  </div>
</template>
