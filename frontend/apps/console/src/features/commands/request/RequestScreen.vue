<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { TakeoverHeader } from "@/shell/index.ts";
import { ApPageHeader, ApRemote, ApStationBar, ApTag } from "@/ui";
import { useCommandAccess } from "../access.ts";
import type { Group } from "../groups/show.ts";
import { GROUP_STATE, GROUP_STATE_WORDS } from "../groups/words.ts";
import ApproveView from "./ApproveView.vue";
import UplinkView from "./UplinkView.vue";
import { headline } from "./uplink.ts";
import { useRequest } from "./useRequest.ts";

/**
 * One command request: C2 Approve (`…/review`, or by default while it awaits a GO) and C3 Uplink &
 * verify (`…/uplink`, or by default afterwards). Shared takeover header with the seven stations.
 */
const route = useRoute();
const access = useCommandAccess();
const groupId = computed(() => String(route.params.requestId));
const req = useRequest(groupId);
const STATIONS = ["Compose", "Check", "Approve", "Release", "Radiate", "Acknowledge", "Verify"];

const reviewing = (g: Group) =>
  route.params.view === "review" || (!route.params.view && g.state === "approval_pending");
function station(g: Group): number {
  if (g.state !== "queued") return 2;
  const p = g.progress;
  if (p.verified === g.target_count) return 6;
  if (p.executed || p.verified || p.no_verifier) return 5;
  if (p.radiating) return 4;
  return 3;
}
const queueRows = computed(() =>
  req.queue.state.value.status === "ready" ? req.queue.state.value.value : [],
);
</script>

<template>
  <ApRemote :state="req.group.state.value" loading-label="LOADING REQUEST…" @retry="req.refetch">
    <template #default="{ value: g }">
      <TakeoverHeader
        :title="reviewing(g) ? 'Review command request' : 'Uplink & verify'"
        :context="`${req.nameOf(g.requested_by.user_id)} · ${GROUP_STATE_WORDS[g.state]}`"
        :close="{ name: 'ops.commands' }"
        close-label="Close"
        title-as="p"
      >
        <template #steps
          ><ApStationBar :steps="STATIONS" :current="station(g)" label="Request stations"
        /></template>
      </TakeoverHeader>
      <ApPageHeader
        :label="reviewing(g) ? undefined : g.title"
        :title="reviewing(g) ? g.title : headline(g)"
      >
        <template #status
          ><ApTag :state="GROUP_STATE[g.state]" :label="GROUP_STATE_WORDS[g.state]"
        /></template>
      </ApPageHeader>
      <ApproveView
        v-if="reviewing(g)"
        :group="g"
        :review="req.review.state.value"
        :queue="queueRows"
        :viewer-id="req.viewerId"
        :can-approve="access.approve"
        :name-of="req.nameOf"
        @decided="req.refetch"
        @retry-review="req.refetch"
      />
      <UplinkView
        v-else
        :group="g"
        :name-of="req.nameOf"
        :can-abort="access.request || access.approve"
        @changed="req.refetch"
      />
    </template>
  </ApRemote>
</template>
