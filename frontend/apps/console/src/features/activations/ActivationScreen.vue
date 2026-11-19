<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import {
  ApBreadcrumb,
  ApCallout,
  ApKeyValue,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTag,
  type ApCrumb,
} from "@/ui";
import ActivationApply from "./ActivationApply.vue";
import ActivationDecide from "./ActivationDecide.vue";
import ActivationOutcome from "./ActivationOutcome.vue";
import ChangesPanel from "./ChangesPanel.vue";
import { fetchActivation, requestedLine, stateTag, type DecidedNote } from "./api.ts";

/** L10 review page: what an app activation applies, who asked, and the second person's decision. */
const props = defineProps<{ requestId: string }>();
const scope = useMissionScope();
const session = useSession();
const key = computed(() => ({ missionId: scope.value.mission.id, requestId: props.requestId }));
const page = useRemoteQuery(key, fetchActivation);
// api: decide/resume fire `activations`; an apply that fails or stalls fires `attention`.
useMissionInvalidation(
  computed(() => scope.value.mission.id),
  ["activations", "attention"],
  page.refetch,
);
const viewer = computed(() => ({
  userId: session.user.id,
  orgAdmin: canAdministerOrganization(session, scope.value.organization),
}));
const note = ref<DecidedNote | null>(null);
const crumbs: readonly ApCrumb[] = [
  { label: "Changes", to: { name: "setup.changes" } },
  { label: "Activation" },
];
function decided(n: DecidedNote) {
  note.value = n;
  page.refetch();
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1000px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApRemote :state="page.state.value" loading-label="Loading activation…" @retry="page.refetch">
      <template #default="{ value }">
        <ApPageHeader
          :label="`${scope.mission.name} · activation · ${value.app?.name ?? 'app'}`"
          :title="value.summary"
          size="reading"
        >
          <ApTag :state="stateTag(value).state" :label="stateTag(value).label" />
        </ApPageHeader>
        <!-- a11y B6: a failed or unconfirmed apply is an alert; the rest a status (#319). -->
        <ApCallout v-if="note" :tone="note.tone" :role="note.failed ? 'alert' : 'status'">{{
          note.text
        }}</ApCallout>
        <ActivationApply
          v-else
          :request-key="key"
          :request="value"
          @resumed="decided"
          @refused="page.refetch"
        />
        <ApPanel index="R1" title="What it activates">
          <ApKeyValue
            :items="[
              { key: 'who', label: 'Requested', value: requestedLine(value) },
              ...value.details.map((d, i) => ({ key: `d${i}`, label: d.label, value: d.value })),
            ]"
            :columns="2"
          />
          <ActivationOutcome :request="value" />
        </ApPanel>
        <ChangesPanel
          v-if="value.configuration_changes"
          :changes="value.configuration_changes"
          :request-key="key"
          index="R2"
        />
        <ActivationDecide
          v-if="value.state === 'approval_pending'"
          :index="value.configuration_changes ? 'R3' : 'R2'"
          :request-key="key"
          :request="value"
          :viewer="viewer"
          @decided="decided"
        />
      </template>
    </ApRemote>
  </div>
</template>
