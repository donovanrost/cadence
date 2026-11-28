<script setup lang="ts">
import { computed, ref } from "vue";
import { useNoteFocus } from "./useNoteFocus.ts";
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
/**
 * #244 (A5, B4): Approve, Reject or a successful Retry apply unmounts the control that had focus (the
 * refetch drops the Decide panel or the Retry button). Focus moves to the outcome note only when it
 * was lost (the kit's refocusFirst; ux's #431 rule): a person who moved on keeps their place.
 */
const noteBox = ref<HTMLElement | null>(null);
// The Decide panel leaves only when the refetch shows the request out of approval_pending (ux).
const focusNote = useNoteFocus(
  noteBox,
  () => page.state.value.status === "ready" && page.state.value.value.state !== "approval_pending",
  () => key.value,
);
function decided(n: DecidedNote) {
  note.value = n;
  page.refetch();
  void focusNote();
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1000px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApRemote :state="page.state.value" loading-label="Loading activation…" @retry="page.refetch">
      <template #default="{ value }">
        <ApPageHeader
          :label="`${scope.mission.name} · activation · app`"
          :title="value.summary"
          size="reading"
        >
          <ApTag :state="stateTag(value).state" :label="stateTag(value).label" />
        </ApPageHeader>
        <!-- a11y B6: a failed or unconfirmed apply is an alert; the rest a status (#319). -->
        <div v-if="note" ref="noteBox" tabindex="-1" data-decided-note>
          <ApCallout :tone="note.tone" :role="note.failed ? 'alert' : 'status'">{{
            note.text
          }}</ApCallout>
        </div>
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
