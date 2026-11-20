<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { failureOutcome, fromDocument, type FormValues } from "@/features/changes/index.ts";
import { fetchSpacecraftDirectory } from "@/features/spacecraft/index.ts";
import { useSession } from "@/shell";
import { ApButton, ApCallout, ApRemote, OutcomeCallout, plural } from "@/ui";
import RequirementGroups from "./RequirementGroups.vue";
import {
  fetchRequirementSchema,
  fieldErrors,
  notActiveLine,
  alreadyCreated,
  saveRequirement,
  withSpacecraftChoices,
  type RequirementDetail,
} from "./requirements.ts";
import { fetchRequirementSupersedes, supersedeSentence } from "./supersedes.ts";
import { buildNested } from "./templates.ts";
import { withoutBlankConstraints } from "./requirements.ts";

/** P4 one-off requirement: new, or a new version (ux ContactPlanning.md; api fb7510be). */
const props = defineProps<{ missionId: MissionId; requirement: RequirementDetail | null }>();
const emit = defineEmits<{ close: [] }>();
const router = useRouter();
const session = useSession();
const rawSchema = useRemoteQuery(() => props.missionId, fetchRequirementSchema);
const directory = useRemoteQuery(() => props.missionId, fetchSpacecraftDirectory);
const schema = computed(() => {
  const s = rawSchema.state.value;
  if (s.status !== "ready") return s;
  const d = directory.state.value;
  const rows = d.status === "ready" ? d.value.spacecraft : [];
  return { ...s, value: withSpacecraftChoices(s.value, rows) };
});
const supersedes = useRemoteQuery(
  () =>
    props.requirement ? { missionId: props.missionId, requirementId: props.requirement.id } : null,
  fetchRequirementSupersedes,
);
const drafts = computed(() =>
  supersedes.state.value.status === "ready"
    ? supersedes.state.value.value.filter((d) => d.state !== "superseded")
    : [],
);
const values = ref<FormValues>({});
const errors = ref<Readonly<Record<string, string>>>({});
const note = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
const busy = ref(false);
watch(
  () => rawSchema.state.value,
  (s) => {
    if (s.status === "ready")
      values.value = fromDocument(
        { kind: "requirement", fields: s.value.fields },
        props.requirement?.content ?? s.value.defaults ?? {},
      );
  },
  { immediate: true },
);
const saveLabel = computed(() => {
  if (!props.requirement) return "Create requirement";
  const next = `Save v${props.requirement.version + 1}`;
  return drafts.value.length > 0
    ? `${next} · supersede ${plural(drafts.value.length, "draft")}`
    : next;
});

/** Set once a new requirement is created: Create stays off, and the note links to it. */
const created = ref<string | null>(null);
/** One create per form open: a retry replays it, and the server answers with the row it made. */
const operationId = crypto.randomUUID();

async function save() {
  const s = rawSchema.state.value;
  if (s.status !== "ready" || busy.value || created.value) return;
  // Every field is sent: an explicit null clears (e.g. no gap limit), the rest restate the version.
  const built = buildNested(
    s.value.fields,
    values.value,
    props.requirement?.content ?? s.value.defaults,
  );
  if (!built.ok) {
    errors.value = built.errors;
    note.value = {
      tone: "caution",
      text: `Fix ${plural(Object.keys(built.errors).length, "highlighted field")} first.`,
    };
    return;
  }
  errors.value = {};
  busy.value = true;
  try {
    const r = await saveRequirement(props.missionId, props.requirement?.id ?? null, {
      content: withoutBlankConstraints(built.document),
      ...(props.requirement
        ? { expected_version: props.requirement.version }
        : { operation_id: operationId }),
    });
    const replayed = r.ok ? null : alreadyCreated(r.error, "requirement_id");
    if (!r.ok && !replayed) {
      errors.value = fieldErrors(r.error);
      return void (note.value = {
        tone: "crit",
        text: notActiveLine(r.error) ?? failureOutcome(r.error, "changed").sentence,
      });
    }
    if (props.requirement) return void emit("close");
    // qa: twice the server created it but the page stayed on New with nothing said, and a second
    // click made a duplicate. Say it's created and lock Create first, whatever the navigation does.
    const id = r.ok ? r.value.id : (replayed ?? "");
    created.value = id;
    note.value = { tone: "nominal", text: "Created." };
    await router
      .push({ name: "setup.contact-planning.requirement", params: { requirementId: id } })
      .catch(() => undefined);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApRemote :state="schema" loading-label="Loading requirement fields…" @retry="rawSchema.refetch">
    <template #default="{ value: s }">
      <RequirementGroups v-model="values" :schema="s" :errors="errors" />
      <ApCallout v-if="requirement && drafts.length > 0" tone="caution">{{
        supersedeSentence(drafts, requirement.version + 1, session.user.id)
      }}</ApCallout>
      <OutcomeCallout v-if="note" :outcome="note">
        <template v-if="created" #action>
          <ApButton
            size="compact"
            :to="{
              name: 'setup.contact-planning.requirement',
              params: { requirementId: created },
            }"
            >Open it</ApButton
          >
        </template>
      </OutcomeCallout>
      <div class="flex flex-wrap gap-2">
        <ApButton
          variant="primary"
          :disabled="busy || created !== null"
          :disabled-reason="created ? 'Created. Open it above.' : 'Saving…'"
          @click="save"
          >{{ saveLabel }}</ApButton
        >
        <ApButton variant="ghost" @click="emit('close')">Cancel</ApButton>
      </div>
    </template>
  </ApRemote>
</template>
