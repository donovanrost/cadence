<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionScope, useSession } from "@/shell";
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
import ActivationDecide from "./ActivationDecide.vue";
import { decisionLine, fetchActivation, requestedLine, stateTag } from "./api.ts";

/** L10 review page: what an app activation applies, who asked, and the second person's decision. */
const props = defineProps<{ requestId: string }>();
const scope = useMissionScope();
const session = useSession();
const key = computed(() => ({ missionId: scope.value.mission.id, requestId: props.requestId }));
const page = useRemoteQuery(key, fetchActivation);
const note = ref<{ tone: "nominal" | "caution"; text: string } | null>(null);
const crumbs: readonly ApCrumb[] = [
  { label: "Changes", to: { name: "setup.changes" } },
  { label: "Activation" },
];
function decided(n: { tone: "nominal" | "caution"; text: string }) {
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
        <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
        <ApPanel index="R1" title="What it activates">
          <ApKeyValue
            :items="[
              { key: 'who', label: 'Requested', value: requestedLine(value) },
              ...value.details.map((d, i) => ({ key: `d${i}`, label: d.label, value: d.value })),
            ]"
            :columns="2"
          />
          <p v-if="decisionLine(value)" class="m-0 mt-3 text-sm text-text-2">
            {{ decisionLine(value) }}
          </p>
        </ApPanel>
        <ActivationDecide
          v-if="value.state === 'approval_pending'"
          :request-key="key"
          :request="value"
          :is-requester="value.requested_by?.id === session.user.id"
          @decided="decided"
        />
      </template>
    </ApRemote>
  </div>
</template>
