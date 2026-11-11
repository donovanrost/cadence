<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import {
  displayValue,
  failureOutcome,
  previewOps,
  refreshConfigState,
  SchemaForm,
  stageChange,
  toValue,
  type FormValues,
} from "@/features/changes/index.ts";
import { fetchSpacecraftDirectory } from "@/features/spacecraft/index.ts";
import { ApButton, ApCallout, ApPanel, ApRemote, ApSelect, ApTextarea } from "@/ui";
import { fieldText, type ProfileDetail } from "./detail.ts";
import { overridableFields, overrideKey, overrideOp, overrideSchemaField } from "./overrides.ts";
import { describePreview } from "./sectionEdit.ts";

/** P3 Add override: one spacecraft, one profile field, its value and why; staged as a change. */
const props = defineProps<{ missionId: string; detail: ProfileDetail }>();
const emit = defineEmits<{ cancel: [] }>();
const router = useRouter();
const missionId = computed(() => props.missionId);
const { state, refetch } = useRemoteQuery(missionId, fetchSpacecraftDirectory);
const spacecraft = computed(() =>
  state.value.status === "ready"
    ? state.value.value.spacecraft
        .filter((r) => r.profile?.id === props.detail.profile.id)
        .map((r) => ({ value: r.id, label: r.name }))
    : [],
);

const fields = overridableFields(props.detail);
const fieldOptions = fields.map((o) => ({
  value: o.field.path,
  label: `${o.field.label} · ${o.section}`,
}));
const spacecraftId = ref("");
const path = ref(fields[0]?.field.path ?? "");
const reason = ref("");
const values = ref<FormValues>({});
const chosen = computed(() => fields.find((o) => o.field.path === path.value)?.field ?? null);
const field = computed(() => (chosen.value ? overrideSchemaField(chosen.value) : null));
const schema = computed(() => ({
  kind: "spacecraft_override",
  fields: field.value ? [field.value] : [],
}));
/** The profile's value in form text, so the form starts there and "unchanged" is visible. */
const profileText = computed(() =>
  field.value && chosen.value?.value != null ? displayValue(field.value, chosen.value.value) : "",
);
watch(path, () => (values.value = { [path.value]: profileText.value }), { immediate: true });

const typed = computed(() =>
  field.value ? toValue(field.value, values.value[path.value] ?? "") : null,
);
const fieldErrors = computed((): Record<string, string> =>
  typed.value && !typed.value.ok && (values.value[path.value] ?? "") !== ""
    ? { [path.value]: typed.value.message }
    : {},
);
const blocked = computed((): string | null => {
  if (spacecraftId.value === "") return "Choose a spacecraft.";
  if (!typed.value) return "Choose a field.";
  if (!typed.value.ok) return typed.value.message;
  if ((values.value[path.value] ?? "") === profileText.value)
    return "That's the profile's value. Choose the value this spacecraft should differ to.";
  if (reason.value.trim() === "") return "Say why this spacecraft differs.";
  return null;
});

const busy = ref(false);
const outcome = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
watch([spacecraftId, path, values, reason], () => (outcome.value = null), { deep: true });
/** ux: Stage is disabled while the last Check said NO-GO, with that line as the reason. */
const noGo = computed(() => (outcome.value?.tone === "crit" ? outcome.value.text : null));
const name = () => spacecraft.value.find((o) => o.value === spacecraftId.value)?.label ?? "";
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
  try {
    const r = await stageChange(props.missionId, {
      summary: `${name()} · override ${chosen.value?.label ?? path.value}`,
      source: { surface: "profile_overrides" },
      ops: [op()],
    });
    if (!r.ok)
      return void (outcome.value = { tone: "crit", text: failureOutcome(r.error, "staged").sentence });
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="P3" title="Add override">
    <div class="flex flex-col gap-4">
      <ApRemote :state="state" loading-label="Loading spacecraft…" @retry="refetch">
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <ApSelect
            v-model="spacecraftId"
            label="Spacecraft"
            mono
            placeholder="Choose…"
            :options="spacecraft"
            :hint="`${spacecraft.length} on ${detail.profile.name}`"
          />
          <ApSelect v-model="path" label="Field" :options="fieldOptions" />
        </div>
      </ApRemote>
      <SchemaForm v-if="field" v-model="values" :schema="schema" :errors="fieldErrors" />
      <p v-if="chosen" class="m-0 text-sm text-text-3">Profile value: {{ fieldText(chosen) }}</p>
      <ApTextarea
        v-model="reason"
        label="Why this spacecraft differs"
        placeholder="Shown on the override and in the change set"
        :rows="2"
        :maxlength="500"
        required
      />
      <ApCallout v-if="outcome" :tone="outcome.tone">{{ outcome.text }}</ApCallout>
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
          >Stage override</ApButton
        >
        <ApButton variant="ghost" @click="emit('cancel')">Cancel</ApButton>
      </div>
      <p v-if="blocked" class="m-0 text-sm text-text-3">{{ blocked }}</p>
    </div>
  </ApPanel>
</template>
