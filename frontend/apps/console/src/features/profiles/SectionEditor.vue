<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import {
  diffEdits,
  failureOutcome,
  previewOps,
  refreshConfigState,
  SchemaForm,
  stageChange,
} from "@/features/changes/index.ts";
import { ApPanel, plural } from "@/ui";
import type { ProfileSection } from "./detail.ts";
import {
  describePreview,
  previewCounts,
  schemaFieldsOf,
  sectionOp,
  sectionValues,
  type PreviewCounts,
} from "./sectionEdit.ts";
import StagedEditAside from "./StagedEditAside.vue";

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
const counts = ref<PreviewCounts | null>(null);
const edits = computed(() => diffEdits(schema, before, values.value));
const dirty = computed(() =>
  fields.filter((f) => (values.value[f.path] ?? "") !== (before[f.path] ?? "")),
);
const errors = computed(() => (edits.value.ok ? {} : edits.value.errors));
const labels = Object.fromEntries(fields.map((f) => [f.path, f.label]));
/** ux: Stage edit is disabled while the last Check said NO-GO, with that line as the reason. */
const noGo = computed(() => (outcome.value?.tone === "crit" ? outcome.value.text : null));
const invalid = computed(() => (edits.value.ok ? null : "Fix the fields first"));
const blocked = computed(() => invalid.value ?? noGo.value);
watch(
  values,
  () => {
    outcome.value = null;
    counts.value = null;
  },
  { deep: true },
);

async function check() {
  if (!edits.value.ok || busy.value) return;
  busy.value = true;
  try {
    const r = await previewOps(
      { missionId: props.missionId, ops: [sectionOp(props.profile.id, edits.value.changes)] },
      new AbortController().signal,
    );
    outcome.value = r.ok
      ? describePreview(r.value, labels, values.value)
      : { tone: "crit", text: failureOutcome(r.error, "changed").sentence };
    counts.value = r.ok ? previewCounts(r.value) : null;
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
  <div class="flex flex-wrap items-start gap-4">
    <ApPanel index="P1" :title="`Edit ${section.label}`" class="min-w-0 flex-[999_1_560px]">
      <SchemaForm v-model="values" :schema="schema" :errors="errors" />
    </ApPanel>
    <StagedEditAside
      v-if="dirty.length > 0"
      class="sticky top-0 min-w-0 flex-[1_1_340px]"
      :dirty="dirty"
      :before="before"
      :values="values"
      :outcome="outcome"
      :counts="counts"
      :busy="busy"
      :invalid="invalid"
      :blocked="blocked"
      @check="check"
      @stage="stage"
      @discard="emit('cancel')"
    />
  </div>
</template>
