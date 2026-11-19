<script setup lang="ts">
import type { ApiError, MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { useRouter, type RouteLocationRaw } from "vue-router";
import { useRemoteQuery } from "@/api";
import { ApButton, ApPanel, ApRemote } from "@/ui";
import { failureOutcome, stageChange, type FailureOutcome } from "./actions.ts";
import FailureOutcomeCallout from "./FailureOutcomeCallout.vue";
import { fieldErrors } from "./fieldErrors.ts";
import type { FormRules, FormState } from "./formRules.ts";
import {
  createDefaults,
  diffEdits,
  fetchKindSchema,
  fromDocument,
  type EditableKind,
  type FormValues,
  type KindSchema,
} from "./kindSchema.ts";
import SchemaForm from "./SchemaForm.vue";
import { refreshConfigState } from "./useConfigState.ts";

/**
 * Edit (entityId + document) or create (entityId null) one entity of a change-set kind. The
 * form comes from the kind schema; staged paths are exactly the schema's (api: conflict checks).
 */
const props = defineProps<{
  missionId: MissionId;
  kind: EditableKind;
  entityId: string | null;
  document: Readonly<Record<string, unknown>>;
  name: string;
  index: string;
  surface: string;
  done: RouteLocationRaw;
  /** Kind-specific form tweaks, e.g. the spacecraft's inactive pinned profile as a choice (L17). */
  prepare?: (schema: KindSchema) => KindSchema;
  /** Kind-specific change rules, e.g. a profile version is staged with its profile (L17). */
  finish?: (
    changes: readonly { path: string; value: unknown }[],
  ) => readonly { path: string; value: unknown }[];
  /** A value the read suggests for one field, offered as 'Suggested: X' + 'Use X' (ux U25). */
  suggestion?: Readonly<{ path: string; value: string }> | null;
  /** The change-set summary in the kind's own words (U79 "Add extra route INU · EARENDIL-389"). */
  summarize?: (
    action: "create" | "update",
    values: FormValues,
    changes: readonly { path: string; value: unknown }[],
  ) => string;
  /** Kind-specific form rules the schema can't say (U83: a transport's listener). */
  rules?: FormRules;
}>();
const router = useRouter();
const fetched = useRemoteQuery(
  () => ({ missionId: props.missionId, kind: props.kind }),
  fetchKindSchema,
);
const schema = {
  refetch: fetched.refetch,
  state: computed(() => {
    const s = fetched.state.value;
    if (s.status !== "ready") return s;
    // A create-only field (a derived point's id) isn't part of an edit (api fa7e9e463).
    const editable = props.entityId
      ? { ...s.value, fields: s.value.fields.filter((f) => f.create_only !== true) }
      : s.value;
    return { ...s, value: props.prepare ? props.prepare(editable) : editable };
  }),
};
const before = ref<FormValues>({});
const values = ref<FormValues>({});
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<FailureOutcome | null>(null);
const busy = ref(false);
watch(
  () => [schema.state.value, props.document] as const,
  ([s, doc]) => {
    if (s.status !== "ready") return;
    const given = fromDocument(s.value, doc);
    // ux: a create preselects required defaults, staged explicitly (they differ from `before`).
    // So does a create's preset document (U79: the page's spacecraft): `before` is blank then.
    before.value = props.entityId ? given : fromDocument(s.value, {});
    values.value = props.entityId ? { ...given } : createDefaults(s.value, given);
  },
  { immediate: true },
);
/** The form as the rules see it; null until the schema is in. */
const formState = (): FormState | null =>
  schema.state.value.status === "ready"
    ? { schema: schema.state.value.value, before: before.value, values: values.value }
    : null;
function edit(next: FormValues) {
  const s = formState();
  values.value = s && props.rules?.reconcile ? props.rules.reconcile({ ...s, values: next }) : next;
}
const notes = computed(() => {
  const s = formState();
  return s && props.rules?.notes ? props.rules.notes(s) : {};
});
const title = computed(() => (props.entityId ? `Edit ${props.name}` : `Add ${props.name}`));
/** Offered until the field holds it; using it only fills the form (staged with the edit). */
const offered = computed(() => {
  const s = props.suggestion;
  return s && (values.value[s.path] ?? "") !== s.value ? s : null;
});
function useSuggestion() {
  const s = offered.value;
  if (s) edit({ ...values.value, [s.path]: s.value });
}
const show = (v: unknown) =>
  v === null ? "cleared" : typeof v === "string" ? v : JSON.stringify(v);

/** Nested document from dotted paths (create). */
function toDocument(changes: readonly { path: string; value: unknown }[]) {
  const doc: Record<string, unknown> = {};
  for (const { path, value } of changes) {
    const keys = path.split(".");
    let at = doc;
    keys.slice(0, -1).forEach((k) => {
      const next = at[k];
      at = (at[k] = next !== null && typeof next === "object" ? next : {}) as Record<
        string,
        unknown
      >;
    });
    at[keys.at(-1) ?? path] = value;
  }
  return doc;
}

function defaultSummary(changes: readonly { path: string; value: unknown }[], state: FormState) {
  const label = props.entityId ? props.name : (values.value.display_name ?? props.name);
  return props.entityId
    ? `${label} · ${changes
        .map((c) => props.rules?.describe?.(c, state) ?? `${c.path} → ${show(c.value)}`)
        .join(", ")}`
    : `Add ${label}`;
}

/** U79: a field's error sits on the field; anything else, and the outcome, in the callout. */
function rejected(error: ApiError) {
  const state = schema.state.value;
  const split =
    state.status === "ready"
      ? fieldErrors(error, new Set(state.value.fields.map((f) => f.path)))
      : null;
  if (!split || Object.keys(split.onFields).length === 0) {
    failure.value = failureOutcome(error, "staged");
    return;
  }
  errors.value = split.onFields;
  failure.value = {
    changed: false,
    sentence: [
      "Nothing was staged.",
      ...split.rest.map((e) => (e.path ? `${e.path}: ${e.message}` : e.message)),
    ].join(" "),
  };
}

async function stage() {
  if (schema.state.value.status !== "ready" || busy.value) return;
  const edits = diffEdits(schema.state.value.value, before.value, values.value);
  if (!edits.ok) return void (errors.value = edits.errors);
  errors.value = {};
  if (edits.changes.length === 0)
    return void (failure.value = { changed: false, sentence: "Nothing changed yet." });
  const state = { schema: schema.state.value.value, before: before.value, values: values.value };
  const finished = props.finish ? props.finish(edits.changes) : edits.changes;
  const changes = props.rules?.finish ? props.rules.finish(finished, state) : finished;
  if (changes.length === 0)
    return void (failure.value = { changed: false, sentence: "Nothing changed yet." });
  busy.value = true;
  failure.value = null;
  try {
    const op = props.entityId
      ? {
          kind: props.kind,
          action: "update" as const,
          entity_id: props.entityId,
          changes,
        }
      : { kind: props.kind, action: "create" as const, document: toDocument(changes) };
    const summary = props.summarize
      ? props.summarize(props.entityId ? "update" : "create", values.value, changes)
      : defaultSummary(changes, state);
    const result = await stageChange(props.missionId, {
      summary,
      source: { surface: props.surface },
      ops: [op],
    });
    if (!result.ok) return void rejected(result.error);
    refreshConfigState(props.missionId);
    await router.push(props.done);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel :index="index" :title="title">
    <!-- The page's own header actions, e.g. U82 Archive…; never a primary button. -->
    <template v-if="$slots.actions" #header>
      <span class="ml-auto flex items-center gap-2"><slot name="actions" /></span>
    </template>
    <ApRemote :state="schema.state.value" loading-label="Loading fields…" @retry="schema.refetch">
      <template #default="{ value: kindSchema }">
        <form class="flex flex-col gap-4" @submit.prevent="stage">
          <SchemaForm
            :model-value="values"
            :schema="kindSchema"
            :errors="errors"
            :notes="notes"
            @update:model-value="edit"
          />
          <p v-if="offered" class="m-0 flex flex-wrap items-center gap-2 text-sm text-text-3">
            Suggested: <span class="font-mono text-readout">{{ offered.value }}</span>
            <ApButton size="compact" @click="useSuggestion">Use {{ offered.value }}</ApButton>
          </p>
          <FailureOutcomeCallout v-if="failure" :outcome="failure" tone="caution" />
          <div class="flex flex-wrap gap-2">
            <ApButton type="submit" variant="primary" :disabled="busy" disabled-reason="Staging…"
              >Stage change</ApButton
            >
            <ApButton :to="done">Cancel</ApButton>
          </div>
          <p class="m-0 text-sm text-text-3">Nothing is live until the change set is applied.</p>
        </form>
      </template>
    </ApRemote>
  </ApPanel>
</template>
