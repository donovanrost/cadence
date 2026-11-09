<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRouter, type RouteLocationRaw } from "vue-router";
import { useRemoteQuery } from "@/api";
import { ApButton, ApCallout, ApPanel, ApRemote } from "@/ui";
import { failureOutcome, stageChange } from "./actions.ts";
import {
  diffEdits,
  fetchKindSchema,
  fromDocument,
  type EditableKind,
  type FormValues,
} from "./kindSchema.ts";
import SchemaForm from "./SchemaForm.vue";
import { refreshConfigState } from "./useConfigState.ts";

/**
 * Edit (entityId + document) or create (entityId null) one entity of a change-set kind. The
 * form comes from the kind schema; staged paths are exactly the schema's (api: conflict checks).
 */
const props = defineProps<{
  missionId: string;
  kind: EditableKind;
  entityId: string | null;
  document: Readonly<Record<string, unknown>>;
  name: string;
  index: string;
  surface: string;
  done: RouteLocationRaw;
}>();
const router = useRouter();
const schema = useRemoteQuery(
  () => ({ missionId: props.missionId, kind: props.kind }),
  fetchKindSchema,
);
const before = ref<FormValues>({});
const values = ref<FormValues>({});
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<string | null>(null);
const busy = ref(false);
watch(
  () => [schema.state.value, props.document] as const,
  ([s, doc]) => {
    if (s.status !== "ready") return;
    before.value = fromDocument(s.value, doc);
    values.value = { ...before.value };
  },
  { immediate: true },
);
const title = computed(() => (props.entityId ? `Edit ${props.name}` : `Add ${props.name}`));
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

async function stage() {
  if (schema.state.value.status !== "ready" || busy.value) return;
  const edits = diffEdits(schema.state.value.value, before.value, values.value);
  if (!edits.ok) return void (errors.value = edits.errors);
  errors.value = {};
  if (edits.changes.length === 0) return void (failure.value = "Nothing changed yet.");
  busy.value = true;
  failure.value = null;
  try {
    const op = props.entityId
      ? {
          kind: props.kind,
          action: "update" as const,
          entity_id: props.entityId,
          changes: edits.changes,
        }
      : { kind: props.kind, action: "create" as const, document: toDocument(edits.changes) };
    const label = props.entityId ? props.name : (values.value.display_name ?? props.name);
    const summary = props.entityId
      ? `${label} · ${edits.changes.map((c) => `${c.path} → ${show(c.value)}`).join(", ")}`
      : `Add ${label}`;
    const result = await stageChange(props.missionId, {
      summary,
      source: { surface: props.surface },
      ops: [op],
    });
    if (!result.ok) return void (failure.value = failureOutcome(result.error, "staged").sentence);
    refreshConfigState(props.missionId);
    await router.push(props.done);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel :index="index" :title="title">
    <ApRemote :state="schema.state.value" loading-label="Loading fields…" @retry="schema.refetch">
      <template #default="{ value: kindSchema }">
        <form class="flex flex-col gap-4" @submit.prevent="stage">
          <SchemaForm v-model="values" :schema="kindSchema" :errors="errors" />
          <ApCallout v-if="failure" tone="caution">{{ failure }}</ApCallout>
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
