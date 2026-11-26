<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { fieldErrors, useRemoteQuery } from "@/api";
import {
  failureOutcome,
  fromDocument,
  SchemaForm,
  type FormValues,
} from "@/features/changes/index.ts";
import {
  ApButton,
  ApCallout,
  ApField,
  ApPanel,
  ApRemote,
  formatCount,
  OutcomeCallout,
  plural,
} from "@/ui";
import { useSession } from "@/shell";
import TargetPicker from "./TargetPicker.vue";
import { decidedLine } from "./decided.ts";
import { fetchTemplateSupersedes, supersedeSentence } from "./supersedes.ts";
import type { TemplateDetail } from "./api.ts";
import { asRecord, draftFromTarget, targetFromDraft, type TargetDraft } from "./targets.ts";
import {
  buildNested,
  fetchTemplateSchema,
  previewTemplate,
  saveTemplate,
  warningText,
  type TemplateSchema,
} from "./templates.ts";
import { alreadyCreated } from "./requirements.ts";

/** New or edit a requirement template (CP3): form generated from the server's template schema. */
const props = defineProps<{ missionId: MissionId; template: TemplateDetail | null }>();
const emit = defineEmits<{ close: [] }>();
const router = useRouter();
const schema = useRemoteQuery(() => props.missionId, fetchTemplateSchema);
const session = useSession();
/** Edits only: which open drafts the next version supersedes (server dry run, writes nothing). */
const supersedes = useRemoteQuery(
  () => (props.template ? { missionId: props.missionId, templateId: props.template.id } : null),
  fetchTemplateSupersedes,
);
const drafts = computed(() =>
  // Already-superseded drafts aren't changed by this save; count only the open ones.
  supersedes.state.value.status === "ready"
    ? supersedes.state.value.value.drafts.filter((d) => d.state !== "superseded")
    : [],
);
/** ux U48: the days this edit leaves alone; none on a create (no dry run) or before api ships it. */
const decided = computed(() => {
  const s = supersedes.state.value;
  const d = s.status === "ready" ? s.value.decided : null;
  return d && props.template ? decidedLine(d, props.template.version + 1) : null;
});
const saveLabel = computed(() => {
  if (!props.template) return "Create template";
  const next = `Save v${props.template.version + 1}`;
  return drafts.value.length > 0
    ? `${next} · supersede ${plural(drafts.value.length, "draft")}`
    : next;
});
const name = ref(props.template?.name ?? "");
const target = ref<TargetDraft>(draftFromTarget(props.template?.target ?? null));
const values = ref<FormValues>({});
const errors = ref<Readonly<Record<string, string>>>({});
const targetError = ref<string | null>(null);
const note = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
const busy = ref(false);
watch(
  schema.state,
  (s) => {
    if (s.status === "ready")
      values.value = fromDocument(
        { kind: "template", fields: s.value.fields },
        asRecord(props.template?.document ?? s.value.defaults),
      );
  },
  { immediate: true },
);

// keyed-by-text: schema group keys, an open set from the server's form layout; an unknown group shows its key
const groupTitles: Readonly<Record<string, string>> = {
  schedule: "Schedule",
  requirement: "Each contact",
  catch_up_policy: "Catch-up",
};
function groups(s: TemplateSchema) {
  const keys = [...new Set(s.meta.map((m) => m.group))];
  return keys.map((key) => ({
    key,
    fields: s.fields.filter((_, i) => s.meta[i]?.group === key && !s.meta[i]?.advanced),
    advanced: s.fields.filter((_, i) => s.meta[i]?.group === key && s.meta[i]?.advanced),
  }));
}

function collect() {
  if (schema.state.value.status !== "ready") return null;
  const t = targetFromDraft(target.value);
  targetError.value = t.ok ? null : t.message;
  const built = buildNested(
    schema.state.value.value.fields,
    values.value,
    props.template?.document ?? schema.state.value.value.defaults,
  );
  errors.value = built.ok ? {} : built.errors;
  const problems = (t.ok ? 0 : 1) + (built.ok ? 0 : Object.keys(built.errors).length);
  if (problems > 0)
    note.value = { tone: "caution", text: `Fix ${plural(problems, "highlighted field")} first.` };
  return t.ok && built.ok ? { target: t.target, document: built.document } : null;
}

async function preview() {
  const input = collect();
  if (!input || busy.value) return;
  busy.value = true;
  try {
    const r = await previewTemplate(props.missionId, input, new AbortController().signal);
    note.value = r.ok
      ? {
          tone: r.value.warnings.length > 0 ? "caution" : "nominal",
          text: `${plural(r.value.spacecraft_count, "spacecraft", "spacecraft")} · ${r.value.contacts_per_day !== null ? `${formatCount(Math.round(r.value.contacts_per_day))} contacts a day on average` : `${formatCount(r.value.contacts)} contacts in the next day`}${r.value.warnings.length ? ` · ${r.value.warnings.map((w) => warningText(w.code)).join(" ")}` : ""}`,
        }
      : { tone: "crit", text: failureOutcome(r.error, "changed").sentence };
  } finally {
    busy.value = false;
  }
}

const canSave = computed(() => name.value.trim().length > 0);
/** One create per form open: a retry replays it, and the server answers with the template it made. */
const operationId = crypto.randomUUID();
async function save() {
  const input = collect();
  if (!input || !canSave.value || busy.value) return;
  busy.value = true;
  try {
    const body = {
      name: name.value.trim(),
      ...input,
      ...(props.template
        ? { expected_version: props.template.version }
        : { operation_id: operationId }),
    };
    const r = await saveTemplate(props.missionId, props.template?.id ?? null, body);
    const replayed = r.ok ? null : alreadyCreated(r.error, "template_id");
    if (!r.ok && !replayed) {
      // A 422 names schema paths (e.g. requirement.max_gap_seconds): show them on their fields.
      errors.value = fieldErrors(r.error);
      return void (note.value = {
        tone: "crit",
        text: failureOutcome(r.error, "changed").sentence,
      });
    }
    if (props.template) emit("close");
    else
      await router.push({
        name: "setup.contact-planning.template",
        params: { templateId: r.ok ? r.value.id : (replayed ?? "") },
      });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApRemote
    :state="schema.state.value"
    loading-label="Loading template fields…"
    @retry="schema.refetch"
  >
    <template #default="{ value: s }">
      <ApPanel index="T0" :title="template ? `Edit ${template.name}` : 'New template'">
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <ApField v-model="name" label="Name" required />
          <TargetPicker v-model="target" :mission-id="missionId" :error="targetError" />
        </div>
      </ApPanel>
      <ApPanel
        v-for="(g, i) in groups(s)"
        :key="g.key"
        :index="`T0.${i + 1}`"
        :title="groupTitles[g.key] ?? g.key"
      >
        <SchemaForm
          v-if="g.fields.length > 0"
          v-model="values"
          :schema="{ kind: 'template', fields: g.fields }"
          :errors="errors"
        />
        <details v-if="g.advanced.length > 0" class="mt-3">
          <summary class="ap-label cursor-pointer">Advanced</summary>
          <div class="mt-3">
            <SchemaForm
              v-model="values"
              :schema="{ kind: 'template', fields: g.advanced }"
              :errors="errors"
            />
          </div>
        </details>
      </ApPanel>
      <ApCallout v-if="decided" tone="info">{{ decided }}</ApCallout>
      <ApCallout v-if="template && drafts.length > 0" tone="caution">{{
        supersedeSentence(drafts, template.version + 1, session.user.id)
      }}</ApCallout>
      <OutcomeCallout v-if="note" :outcome="note" />
      <div class="flex flex-wrap gap-2">
        <ApButton :disabled="busy" disabled-reason="Working…" @click="preview">Preview</ApButton>
        <ApButton
          variant="primary"
          :disabled="busy || !canSave"
          :disabled-reason="canSave ? 'Saving…' : 'Name the template first.'"
          @click="save"
          >{{ saveLabel }}</ApButton
        >
        <ApButton variant="ghost" @click="emit('close')">Cancel</ApButton>
      </div>
    </template>
  </ApRemote>
</template>
