<script setup lang="ts">
import { computed, ref, shallowRef } from "vue";
import { useRoute } from "vue-router";
import { describeApiError, useRemoteQuery } from "@/api/index.ts";
import { TakeoverHeader, useMissionScope } from "@/shell/index.ts";
import { ApButton, ApCallout, ApEmptyState, ApPanel, ApRemote, ApStationBar } from "@/ui";
import { TelemetryDegraded, useFleet } from "@/features/fleet/index.ts";
import { useCommandAccess } from "../access.ts";
import { catalogRevisionWords, fetchCommand } from "../api.ts";
import { fetchEndpoints, type TargetEndpoints } from "../groups/api.ts";
import DeliveryPanel from "./DeliveryPanel.vue";
import PreflightPanel from "./PreflightPanel.vue";
import StackPanel from "./StackPanel.vue";
import type { Release } from "./draft.ts";
import SummaryPanel from "./SummaryPanel.vue";
import TargetsPanel from "./TargetsPanel.vue";
import { checkItem, move, newItem, type StackItem } from "./stack.ts";
import { queryFromRoute, resolveTargets, type TargetQuery } from "./targets.ts";
import { useComposeRequest } from "./useComposeRequest.ts";
import { resendFrom, useResend } from "./useResend.ts";

/**
 * C1 Compose / J3 Command a group (Command.md, DECISIONS #31: every request is a group). Targets
 * by live query, a catalog-driven stack, the server's preflight (M18) re-run on every change, each
 * target's next contact, and the summary. Submit (M16) sends the digest of the checks on screen.
 */
const scope = useMissionScope();
const route = useRoute();
const access = useCommandAccess();
const missionId = computed(() => scope.value.mission.id);
const fleet = useFleet(missionId);
const rows = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);

const query = ref<TargetQuery>(queryFromRoute(route.query));
const targets = computed(() => resolveTargets(rows.value, query.value));
const stack = ref<StackItem[]>([]);
/** The stack row whose argument form is open; a newly added command opens itself (ux 5). */
const openKey = ref<string | null>(null);
const revision = ref<string | null>(null);
const catalogRev = ref<string | null>(null);
const adding = ref(false);
const addError = shallowRef<string | null>(null);
async function add(commandId: string) {
  adding.value = true;
  addError.value = null;
  try {
    const result = await fetchCommand(missionId.value, commandId);
    if (!result.ok) addError.value = describeApiError(result.error);
    else if (result.value.command) {
      revision.value = result.value.revision_id;
      catalogRev.value = catalogRevisionWords(result.value.catalog_revision);
      const item = newItem(result.value.command);
      stack.value = [...stack.value, item];
      openKey.value = item.command.arguments.length ? item.key : null;
    }
  } finally {
    adding.value = false;
  }
}
const onAdd = (id: string) => add(id).catch((e: unknown) => console.error("Add command failed", e));
const setValues = (key: string, values: Record<string, string>) =>
  (stack.value = stack.value.map((i) => (i.key === key ? { ...i, values } : i)));

const release = ref<Release>({ mode: "next_contact", notBefore: null });
const approver = ref("");
const log = ref("");
const title = ref(typeof route.query.title === "string" ? route.query.title : "");
/** Uplink endpoints per target (DECISIONS #41) and the operator's explicit overrides. */
const overrides = ref<Record<string, string>>({});
const endpointRead = useRemoteQuery(
  () => (targets.value.length ? targets.value.map((sc) => sc.id).join(",") : null),
  (ids, signal) => fetchEndpoints(missionId.value, ids.split(","), signal),
);
const endpoints = computed(
  () =>
    new Map<string, TargetEndpoints>(
      endpointRead.state.value.status === "ready"
        ? endpointRead.state.value.value.map((e) => [e.spacecraft_id, e])
        : [],
    ),
);
function setOverride(spacecraftId: string, endpointId: string | null) {
  const { [spacecraftId]: _drop, ...rest } = overrides.value;
  overrides.value = endpointId === null ? rest : { ...rest, [spacecraftId]: endpointId };
}
const resend = useResend(missionId, resendFrom(route.query.from), {
  query,
  stack,
  title,
  log,
  approver,
  release,
});
const {
  draft,
  preflight,
  nameOf,
  contacts,
  secondGo,
  acks,
  ack,
  blocked,
  submission,
  send,
  check,
} = useComposeRequest(missionId, rows, targets, query, stack, {
  title,
  log,
  release,
  approver,
  sentBackFrom: resend.sentBackFrom,
  endpoints: overrides,
});

const steps = computed(() => [
  `Targets · ${targets.value.length}`,
  `Commands · ${stack.value.length}`,
  "GO / NO-GO",
  "Arm & uplink",
]);
const current = computed(() =>
  targets.value.length === 0
    ? 0
    : stack.value.length === 0 || stack.value.some((i) => !checkItem(i).ok)
      ? 1
      : blocked.value === null
        ? 3
        : 2,
);
const context = computed(() => {
  const only =
    query.value.explicit.length === 1
      ? rows.value.find((sc) => sc.id === query.value.explicit[0])
      : undefined;
  return only ? `Uplink sequence · for ${only.name}` : "Uplink sequence · new";
});
const close = computed(() => {
  const only =
    query.value.explicit.length === 1
      ? rows.value.find((sc) => sc.id === query.value.explicit[0])
      : undefined;
  return only
    ? { name: "ops.spacecraft", params: { scId: String(only.scid) } }
    : { name: "ops.commands" };
});
</script>

<template>
  <TakeoverHeader
    title="New command request"
    :context="context"
    :close="close"
    close-label="Close and keep nothing"
    title-as="h1"
  >
    <template v-if="access.request" #steps
      ><ApStationBar :steps="steps" :current="current" label="Sequence steps"
    /></template>
  </TakeoverHeader>
  <!-- DECISIONS #38: gate on the capabilities the server reports, nothing else. -->
  <ApPanel v-if="!access.request" index="C0" title="No command access" flush>
    <ApEmptyState
      state="off"
      headline="You can't command on this mission"
      :sentence="`Requesting commands needs operate access to a mission in ${scope.organization.name}. An organization admin can grant it.`"
    >
      <ApButton size="compact" :to="close">Back</ApButton>
    </ApEmptyState>
  </ApPanel>
  <template v-else>
    <!-- Mobile.md: building new uplink sequences is desktop-only by design (ux pass 2 #3). -->
    <ApPanel index="C0" title="Desktop only" flush class="md:hidden">
      <ApEmptyState
        headline="New uplink sequences are desktop only, by design"
        sentence="Approve requests and give GO / NO-GO from the phone; compose and arm sequences at a console."
      >
        <ApButton size="compact" :to="close">Back</ApButton>
      </ApEmptyState>
    </ApPanel>
    <div
      class="grid min-h-0 flex-1 grid-cols-1 gap-3 max-md:hidden console:grid-cols-[minmax(0,1fr)_360px]"
    >
      <div class="flex min-h-0 flex-col gap-3 overflow-auto">
        <ApCallout v-if="resend.notice.value" :tone="resend.notice.value.tone">{{
          resend.notice.value.text
        }}</ApCallout>
        <div class="grid grid-cols-1 items-start gap-3 console:grid-cols-2">
          <!-- Only targets need the fleet read; the stack and catalog work while it loads or fails. -->
          <ApRemote
            :state="fleet.state.value"
            loading-label="LOADING FLEET…"
            @retry="fleet.refetch"
          >
            <TelemetryDegraded
              v-if="fleet.state.value.status === 'ready'"
              :telemetry="fleet.state.value.value.telemetry"
            />
            <TargetsPanel
              :fleet="rows"
              :query="query"
              :targets="targets"
              @change="(q) => (query = q)"
            />
          </ApRemote>
          <ApCallout v-if="addError" tone="caution"
            >Couldn't add that command: {{ addError }}</ApCallout
          >
          <StackPanel
            v-model:open="openKey"
            :items="stack"
            :revision="revision"
            :catalog-rev="catalogRev"
            :adding="adding"
            @add="onAdd"
            @change="setValues"
            @move="(i, by) => (stack = move(stack, i, by))"
            @remove="(key) => (stack = stack.filter((s) => s.key !== key))"
          />
        </div>
        <PreflightPanel
          :state="preflight.state.value"
          :checking="preflight.checking.value"
          :ready="draft !== null"
          :name-of="nameOf"
          :acks="acks"
          @retry="preflight.refetch"
          @ack="ack"
        />
        <DeliveryPanel
          :targets="targets"
          :contacts="contacts"
          :endpoints="endpoints"
          :overrides="overrides"
          @override="setOverride"
        />
      </div>
      <SummaryPanel
        v-model:release="release"
        v-model:approver="approver"
        v-model:log="log"
        v-model:title="title"
        :targets="targets.length"
        :commands="stack.length"
        :second-go="secondGo"
        :blocked="blocked"
        :submit="submission.state.value"
        @send="send"
        @check="check"
      />
    </div>
  </template>
</template>
