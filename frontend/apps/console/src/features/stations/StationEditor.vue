<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import {
  diffEdits,
  failureOutcome,
  fetchKindSchema,
  fromDocument,
  refreshConfigState,
  SchemaForm,
  stageChange,
  type FormValues,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApPanel, ApRemote } from "@/ui";
import type { Station } from "./api.ts";

/** Edit or add a station; the change stages into the mission's change set (Changes.md §1). */
const props = defineProps<{ missionId: string; station: Station | null }>();
const router = useRouter();
const schema = useRemoteQuery(
  () => ({ missionId: props.missionId, kind: "ground_station" as const }),
  fetchKindSchema,
);
const before = ref<FormValues>({});
const values = ref<FormValues>({});
const errors = ref<Readonly<Record<string, string>>>({});
const failure = ref<string | null>(null);
const busy = ref(false);
watch(
  () => [schema.state.value, props.station] as const,
  ([s, station]) => {
    if (s.status !== "ready") return;
    before.value = fromDocument(s.value, station ?? {});
    values.value = { ...before.value };
  },
  { immediate: true },
);
const title = computed(() =>
  props.station ? `Edit ${props.station.display_name}` : "Add station",
);

async function stage() {
  if (schema.state.value.status !== "ready" || busy.value) return;
  const edits = diffEdits(schema.state.value.value, before.value, values.value);
  if (!edits.ok) return void (errors.value = edits.errors);
  errors.value = {};
  if (edits.changes.length === 0) return void (failure.value = "Nothing changed yet.");
  busy.value = true;
  failure.value = null;
  try {
    const name = props.station?.display_name ?? values.value.display_name ?? "station";
    const op = props.station
      ? {
          kind: "ground_station" as const,
          action: "update" as const,
          entity_id: props.station.id,
          changes: edits.changes,
        }
      : {
          kind: "ground_station" as const,
          action: "create" as const,
          document: Object.fromEntries(edits.changes.map((c) => [c.path, c.value])),
        };
    const result = await stageChange(props.missionId, {
      summary: props.station
        ? `${name} · ${edits.changes.map((c) => `${c.path} → ${c.value === null ? "cleared" : String(c.value)}`).join(", ")}`
        : `Add station ${name}`,
      source: { surface: "stations" },
      ops: [op],
    });
    if (!result.ok) return void (failure.value = failureOutcome(result.error, "staged").sentence);
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.stations" });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="G2" :title="title">
    <ApRemote :state="schema.state.value" loading-label="Loading fields…" @retry="schema.refetch">
      <template #default="{ value: kindSchema }">
        <form class="flex flex-col gap-4" @submit.prevent="stage">
          <SchemaForm v-model="values" :schema="kindSchema" :errors="errors" />
          <ApCallout v-if="failure" tone="caution">{{ failure }}</ApCallout>
          <div class="flex flex-wrap gap-2">
            <ApButton type="submit" variant="primary" :disabled="busy" disabled-reason="Staging…"
              >Stage change</ApButton
            >
            <ApButton :to="{ name: 'setup.stations' }">Cancel</ApButton>
          </div>
          <p class="m-0 text-sm text-text-3">Nothing is live until the change set is applied.</p>
        </form>
      </template>
    </ApRemote>
  </ApPanel>
</template>
