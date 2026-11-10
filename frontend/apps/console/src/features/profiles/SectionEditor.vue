<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import {
  diffEdits,
  failureOutcome,
  previewOps,
  refreshConfigState,
  SchemaForm,
  stageChange,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApPanel, plural } from "@/ui";
import type { ProfileSection } from "./detail.ts";
import { describePreview, schemaFieldsOf, sectionOp, sectionValues } from "./sectionEdit.ts";

/** Profile.md P1 edit + P4 staged edit: one section's form, its dry run, and Stage edit. */
const props = defineProps<{
  missionId: string;
  profile: Readonly<{ id: string; name: string }>;
  section: ProfileSection;
}>();
const emit = defineEmits<{ cancel: [] }>();
const router = useRouter();
const fields = schemaFieldsOf(props.section);
const schema = { kind: "spacecraft_profile", fields };
const before = sectionValues(props.section, fields);
const values = ref({ ...before });
const busy = ref(false);
const outcome = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
const edits = computed(() => diffEdits(schema, before, values.value));
const dirty = computed(() =>
  fields.filter((f) => (values.value[f.path] ?? "") !== (before[f.path] ?? "")),
);
const errors = computed(() => (edits.value.ok ? {} : edits.value.errors));

async function check() {
  if (!edits.value.ok || busy.value) return;
  busy.value = true;
  try {
    const r = await previewOps(
      { missionId: props.missionId, ops: [sectionOp(props.profile.id, edits.value.changes)] },
      new AbortController().signal,
    );
    outcome.value = r.ok
      ? describePreview(r.value)
      : { tone: "crit", text: failureOutcome(r.error, "changed").sentence };
  } finally {
    busy.value = false;
  }
}

async function stage() {
  if (!edits.value.ok || edits.value.changes.length === 0 || busy.value) return;
  busy.value = true;
  try {
    const r = await stageChange(props.missionId, {
      summary: `${props.profile.name} · ${props.section.label} (${plural(edits.value.changes.length, "field")})`,
      source: { surface: "profile_section", section: props.section.key },
      ops: [sectionOp(props.profile.id, edits.value.changes)],
    });
    if (!r.ok)
      return void (outcome.value = {
        tone: "crit",
        text: failureOutcome(r.error, "staged").sentence,
      });
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="P1" :title="`Edit ${section.label}`">
    <SchemaForm v-model="values" :schema="schema" :errors="errors" />
  </ApPanel>
  <ApPanel
    v-if="dirty.length > 0"
    index="P4"
    title="Staged edit"
    :meta="plural(dirty.length, 'field')"
  >
    <div class="flex flex-col gap-3">
      <ul class="m-0 list-none p-0 font-mono text-sm">
        <li v-for="f in dirty" :key="f.path" class="py-0.5 text-text-2">
          {{ f.label }} <span class="text-text-4 line-through">{{ before[f.path] || "—" }}</span> →
          <span class="text-readout">{{ values[f.path] || "—" }}</span>
        </li>
      </ul>
      <ApCallout v-if="outcome" :tone="outcome.tone">{{ outcome.text }}</ApCallout>
      <div class="flex flex-wrap gap-3">
        <ApButton
          :disabled="busy || !edits.ok"
          disabled-reason="Fix the fields first"
          @click="check"
          >Check</ApButton
        >
        <ApButton
          variant="primary"
          :disabled="busy || !edits.ok"
          disabled-reason="Fix the fields first"
          @click="stage"
          >Stage edit</ApButton
        >
        <ApButton variant="ghost" @click="emit('cancel')">Discard</ApButton>
      </div>
    </div>
  </ApPanel>
</template>
