<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { fieldErrors, useRemoteQuery } from "@/api";
import { SchemaForm, type FormValues } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApEmptyState, ApField, ApPanel, ApRemote } from "@/ui";
import PolicyDecision from "./PolicyDecision.vue";
import {
  buildDocument,
  fetchPolicy,
  groups,
  groupSummaries,
  groupTitles,
  initialValues,
  policySaveFailure,
  REASON_MAX,
  savePolicy,
} from "./policy.ts";

/** Policy tab (CP2): grouped fields from the server schema; save makes a version needing approval. */
const props = defineProps<{ missionId: MissionId }>();
const { state, refetch } = useRemoteQuery(() => props.missionId, fetchPolicy);
const values = ref<FormValues>({});
const errors = ref<Readonly<Record<string, string>>>({});
const busy = ref(false);
/** ux U20: the saver's optional note, stored with the version (api 7e454da56). */
const reason = ref("");
const reasonError = ref<string | null>(null);
const note = ref<{ tone: "nominal" | "crit"; text: string } | null>(null);
watch(
  state,
  (s) => {
    if (s.status === "ready") values.value = initialValues(s.value);
  },
  { immediate: true },
);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);

async function save() {
  if (state.value.status !== "ready" || busy.value) return;
  const policy = state.value.value;
  const built = buildDocument(policy, values.value);
  if (!built.ok) return void (errors.value = built.errors);
  errors.value = {};
  const why = reason.value.trim();
  reasonError.value = why.length > REASON_MAX ? `Use at most ${REASON_MAX} characters.` : null;
  if (reasonError.value) return;
  busy.value = true;
  try {
    const result = await savePolicy(props.missionId, {
      document: built.document,
      expected_version: policy.version,
      reason: why,
    });
    if (result.ok) reason.value = "";
    else reasonError.value = fieldErrors(result.error)["reason"] ?? null;
    note.value = result.ok
      ? {
          tone: "nominal",
          text: `Saved as v${result.value.version}. It's active once another admin approves it.`,
        }
      : { tone: "crit", text: policySaveFailure(result.error) };
    refetch();
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel v-if="notProvided" index="P4" title="Policy" flush>
    <ApEmptyState state="off" headline="Policy not available in the console yet" />
  </ApPanel>
  <ApRemote v-else :state="state" loading-label="Loading policy…" @retry="refetch">
    <template #default="{ value: policy }">
      <PolicyDecision :mission-id="missionId" :policy="policy" @decided="refetch" />
      <ApPanel
        v-for="(g, i) in groups(policy)"
        :key="g.key"
        :index="`P4.${i + 1}`"
        :title="groupTitles[g.key] ?? g.key"
      >
        <SchemaForm
          v-if="g.fields.length > 0"
          v-model="values"
          :schema="{ kind: 'policy', fields: g.fields }"
          :errors="errors"
        />
        <p v-if="g.fields.length === 0" class="m-0 text-md text-text-3">
          {{
            groupSummaries[g.key] ?? "These are advanced settings; the defaults suit most missions."
          }}
        </p>
        <details v-if="g.advanced.length > 0" :class="g.fields.length > 0 ? 'mt-3' : 'mt-2'">
          <summary class="ap-label cursor-pointer">
            {{ g.fields.length === 0 ? `Show ${g.advanced.length} settings` : "Advanced" }}
          </summary>
          <div class="mt-3">
            <SchemaForm
              v-model="values"
              :schema="{ kind: 'policy', fields: g.advanced }"
              :errors="errors"
            />
          </div>
        </details>
      </ApPanel>
      <ApPanel
        v-if="policy.permissions.includes('planning.edit')"
        index="P6"
        :title="policy.version === null ? 'Create policy' : 'Save a new version'"
      >
        <div class="flex flex-col gap-3">
          <ApField
            v-model="reason"
            label="Why"
            hint="Recorded with the version"
            :error="reasonError"
          />
          <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
          <div>
            <ApButton variant="primary" :disabled="busy" disabled-reason="Saving…" @click="save">{{
              policy.version === null ? "Create policy" : `Save as v${(policy.version ?? 0) + 1}`
            }}</ApButton>
          </div>
          <p class="m-0 font-mono text-xs text-text-4 uppercase">
            Applies to drafts started after it's active<template
              v-if="policy.active_version !== null"
            >
              · v{{ policy.active_version }} kept</template
            >
          </p>
        </div>
      </ApPanel>
      <p v-else class="m-0 text-sm text-text-3">Org admins change contact planning.</p>
    </template>
  </ApRemote>
</template>
