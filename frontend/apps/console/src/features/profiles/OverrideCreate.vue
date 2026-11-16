<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import {
  displayValue,
  FailureOutcomeCallout,
  failureOutcome,
  previewOps,
  refreshConfigState,
  stageChange,
  toValue,
  type FailureOutcome,
  type FormValues,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApPanel, ApTextarea } from "@/ui";
import type { ProfileDetail } from "./detail.ts";
import OverrideTarget from "./OverrideTarget.vue";
import OverrideValue from "./OverrideValue.vue";
import {
  existingLine,
  existingOverride,
  overridableFields,
  overrideKey,
  overrideOp,
  overrideSchemaField,
} from "./overrides.ts";
import { describePreview } from "./sectionEdit.ts";

/** P3 Add override (Profile.md): one spacecraft, one profile field, its value and why. */
const props = defineProps<{ missionId: MissionId; detail: ProfileDetail }>();
const emit = defineEmits<{ cancel: [] }>();
const router = useRouter();
const target = ref<Readonly<{ id: string; name: string }> | null>(null);
const spacecraftId = computed(() => target.value?.id ?? "");

const fields = overridableFields(props.detail);
const fieldOptions = fields.map((o) => ({
  value: o.field.path,
  label: `${o.field.label} · ${o.section}`,
}));
const path = ref(fields[0]?.field.path ?? "");
const reason = ref("");
const values = ref<FormValues>({});
const chosen = computed(() => fields.find((o) => o.field.path === path.value)?.field ?? null);
const field = computed(() => (chosen.value ? overrideSchemaField(chosen.value) : null));
const asText = (v: unknown) => (field.value && v != null ? displayValue(field.value, v) : "");
const profileText = computed(() => asText(chosen.value?.value));
/** ux: an override the spacecraft already holds is shown and changed, never replaced silently. */
const existing = computed(() => existingOverride(props.detail, spacecraftId.value, path.value));
const existingText = computed(() =>
  existing.value ? existingLine(existing.value, chosen.value ?? undefined) : null,
);
watch(
  [path, existing],
  () => {
    const start = existing.value ? asText(existing.value.spacecraft_value) : profileText.value;
    values.value = { [path.value]: start };
  },
  { immediate: true },
);

const typed = computed(() =>
  field.value ? toValue(field.value, values.value[path.value] ?? "") : null,
);
const fieldErrors = computed((): Record<string, string> =>
  typed.value && !typed.value.ok && (values.value[path.value] ?? "") !== ""
    ? { [path.value]: typed.value.message }
    : {},
);
const blocked = computed((): string | null => {
  const text = values.value[path.value] ?? "";
  if (spacecraftId.value === "") return "Choose a spacecraft.";
  if (!typed.value) return "Choose a field.";
  if (!typed.value.ok) return typed.value.message;
  if (text === profileText.value)
    return "Same as the profile's value. Enter the value this spacecraft should use.";
  if (reason.value.trim() === "") return "Say why this spacecraft differs.";
  const same = existing.value;
  if (same && text === asText(same.spacecraft_value) && reason.value.trim() === same.reason)
    return "That's its override already.";
  return null;
});

const busy = ref(false);
const outcome = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
/** A refused or unclear Stage, with its link (e.g. U79 'Open change set'). */
const failure = ref<FailureOutcome | null>(null);
watch(
  [target, path, values, reason],
  () => {
    outcome.value = null;
    failure.value = null;
  },
  { deep: true },
);
/** ux: Stage is disabled while the last Check said NO-GO, with that line as the reason. */
const noGo = computed(() => (outcome.value?.tone === "crit" ? outcome.value.text : null));
const op = () =>
  overrideOp(spacecraftId.value, path.value, {
    value: typed.value?.ok ? typed.value.value : null,
    reason: reason.value.trim(),
  });

async function check() {
  if (blocked.value !== null || busy.value) return;
  busy.value = true;
  try {
    const key = overrideKey(path.value);
    const r = await previewOps(
      { missionId: props.missionId, ops: [op()] },
      new AbortController().signal,
    );
    outcome.value = r.ok
      ? describePreview(
          r.value,
          { [key]: chosen.value?.label ?? key },
          { [key]: values.value[path.value] ?? "" },
        )
      : { tone: "crit", text: failureOutcome(r.error, "changed").sentence };
  } finally {
    busy.value = false;
  }
}

async function stage() {
  if (blocked.value !== null || busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const verb = existing.value ? "change override" : "override";
    const r = await stageChange(props.missionId, {
      summary: `${target.value?.name ?? ""} · ${verb} ${chosen.value?.label ?? path.value}`,
      source: { surface: "profile_overrides" },
      ops: [op()],
    });
    if (!r.ok) return void (failure.value = failureOutcome(r.error, "staged"));
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel title="Add override">
    <div class="flex flex-col gap-4">
      <OverrideTarget
        v-model:spacecraft="target"
        v-model:path="path"
        :mission-id="missionId"
        :profile="detail.profile"
        :field-options="fieldOptions"
      />
      <OverrideValue
        v-if="field && chosen"
        v-model="values"
        :field="field"
        :profile-field="chosen"
        :errors="fieldErrors"
        :existing="existingText"
      />
      <ApTextarea
        v-model="reason"
        label="Why this spacecraft differs"
        hint="Shown on the override and in the change set."
        :rows="2"
        :maxlength="500"
        required
      />
      <ApCallout v-if="outcome" :tone="outcome.tone">{{ outcome.text }}</ApCallout>
      <FailureOutcomeCallout v-if="failure" :outcome="failure" />
      <div class="flex flex-wrap gap-3">
        <ApButton
          :disabled="busy || blocked !== null"
          :disabled-reason="blocked ?? 'Checking…'"
          @click="check"
          >Check</ApButton
        >
        <ApButton
          variant="primary"
          :disabled="busy || blocked !== null || noGo !== null"
          :disabled-reason="noGo ?? blocked ?? 'Staging…'"
          @click="stage"
          >{{ existing ? "Stage change" : "Stage override" }}</ApButton
        >
        <ApButton variant="ghost" @click="emit('cancel')">Cancel</ApButton>
      </div>
      <p v-if="blocked" class="m-0 text-sm text-text-3">{{ blocked }}</p>
    </div>
  </ApPanel>
</template>
