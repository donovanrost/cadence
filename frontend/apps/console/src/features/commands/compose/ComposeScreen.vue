<script setup lang="ts">
import { computed, nextTick, ref, shallowRef, watch } from "vue";
import { onBeforeRouteLeave, useRoute, useRouter, type RouteLocationRaw } from "vue-router";
import { describeApiError } from "@/api/index.ts";
import { useTargetEndpoints } from "./useTargetEndpoints.ts";
import { TakeoverHeader, useMissionScope } from "@/shell/index.ts";
import { ApButton, ApCallout, ApEmptyState, ApPanel, ApRemote, ApStationBar } from "@/ui";
import { TelemetryDegraded, useFleet } from "@/features/fleet/index.ts";
import { useCommandAccess } from "../access.ts";
import { catalogRevisionWords, fetchCommand } from "../api.ts";
import { PRIORITY_NORMAL } from "../priority.ts";
import { resolvedByCommand } from "../groups/resolved.ts";
import ConfirmDialog from "./ConfirmDialog.vue";
import DeliveryPanel from "./DeliveryPanel.vue";
import DraftNotices from "./DraftNotices.vue";
import PreflightPanel from "./PreflightPanel.vue";
import StackPanel from "./StackPanel.vue";
import type { Release } from "./draft.ts";
import SummaryPanel from "./SummaryPanel.vue";
import TargetsPanel from "./TargetsPanel.vue";
import { checkItem, move, moveTo, newItem, type StackItem } from "./stack.ts";
import { queryFromRoute, resolveTargets, type TargetQuery } from "./targets.ts";
import type { ComposeFields, Restored } from "./saved.ts";
import { closeLabel, draftLine, savedWhen, useComposeDraft } from "./useComposeDraft.ts";
import { useComposeRequest } from "./useComposeRequest.ts";
import type { Preflight } from "../groups/api.ts";
import { groupsAt, spanText, targetRevisions } from "../groups/verifierGroups.ts";
import { onlyFrom, resendFrom, useResend } from "./useResend.ts";

/**
 * C1 Compose / J3 Command a group (Command.md, DECISIONS #31: every request is a group). Targets
 * by live query, a catalog-driven stack, the server's preflight (M18) re-run on every change, each
 * target's next contact, and the summary. Submit (M16) sends the digest of the checks on screen.
 */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
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
const setPerTarget = (key: string, perTarget: StackItem["perTarget"]) =>
  (stack.value = stack.value.map((i) => (i.key === key ? { ...i, perTarget } : i)));

const release = ref<Release>({
  mode: "next_contact",
  notBefore: null,
  expiresAt: null,
  priority: PRIORITY_NORMAL,
});
const approver = ref("");
const log = ref("");
const title = ref(typeof route.query.title === "string" ? route.query.title : "");
/** Uplink endpoints per target (DECISIONS #41) and the operator's explicit overrides. */
const overrides = ref<Record<string, string>>({});
const endpoints = useTargetEndpoints(missionId, () => targets.value.map((sc) => sc.id));
function setOverride(spacecraftId: string, endpointId: string | null) {
  const { [spacecraftId]: _drop, ...rest } = overrides.value;
  overrides.value = endpointId === null ? rest : { ...rest, [spacecraftId]: endpointId };
}
const resend = useResend(
  missionId,
  resendFrom(route.query.from),
  {
    query,
    stack,
    title,
    log,
    approver,
    release,
  },
  onlyFrom(route.query.only),
);
/** Autosave (commanding.md §Compose draft): `?draft=resume` from the Commands list restores it. */
const fields = computed<ComposeFields>(() => ({
  title: title.value,
  log: log.value,
  query: query.value,
  endpoints: overrides.value,
  stack: stack.value,
  release: release.value,
  approver: approver.value,
  sentBackFrom: resend.sentBackFrom.value,
}));
function applyDraft(r: Restored) {
  const f = r.fields;
  title.value = f.title;
  log.value = f.log;
  query.value = f.query;
  overrides.value = { ...f.endpoints };
  stack.value = [...f.stack];
  release.value = f.release;
  approver.value = f.approver;
  resend.sentBackFrom.value = f.sentBackFrom;
  revision.value = r.revisionId;
  catalogRev.value = r.catalogRev;
  openKey.value = null;
}
const saved = useComposeDraft(missionId, fields, applyDraft, route.query.draft === "resume");
/**
 * Palette `>` (lead): `?command=<catalog id>` adds that command once, as if picked in the catalog
 * search, with no targets. A resend or a resumed draft wins. The param is dropped so a reload
 * doesn't add it twice.
 */
const fromPalette = typeof route.query.command === "string" ? route.query.command : null;
if (fromPalette !== null) {
  const { command: _used, ...rest } = route.query;
  router.replace({ query: rest }).catch((e: unknown) => console.error("Navigation failed", e));
  if (resendFrom(route.query.from) === null && route.query.draft !== "resume") onAdd(fromPalette);
}
// ux (1): a resend's prefill is the origin's values, not the operator's first edit.
watch(resend.sentBackFrom, (id) => {
  if (id !== null) void nextTick(saved.rebase);
});
/** ux (3): both Discards confirm first; closing saves first and asks only if that fails. */
const discardDialog = ref<InstanceType<typeof ConfirmDialog> | null>(null);
const leaveDialog = ref<InstanceType<typeof ConfirmDialog> | null>(null);
const discardAt = ref<string | null>(null);
async function confirmDiscard(at: string | null) {
  discardAt.value = at;
  return (await discardDialog.value?.ask()) === true;
}
async function discardAndClose() {
  if (!(await confirmDiscard(saved.savedAt.value)) || !(await saved.discard())) return;
  await router.push(close.value).catch((e: unknown) => console.error("Navigation failed", e));
}
async function discardOffered() {
  if (await confirmDiscard(saved.offered.value?.saved_at ?? null)) await saved.discard();
}
onBeforeRouteLeave(async () => (await saved.flush()) || (await leaveDialog.value?.ask()) === true);
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
} = useComposeRequest(
  missionId,
  rows,
  targets,
  query,
  stack,
  {
    title,
    log,
    release,
    approver,
    sentBackFrom: resend.sentBackFrom,
    endpoints: overrides,
  },
  saved,
);

/**
 * U51: the last preflight answer's verifier groups and target revisions. Kept while a re-run
 * checks, so the rows and tags don't flicker on every edit.
 */
const lastPreflight = shallowRef<Preflight | null>(null);
watch(
  () => preflight.state.value,
  (st) => {
    if (st.status === "ready") lastPreflight.value = st.value;
  },
  { immediate: true },
);
const groupsAtStack = (position: number) => groupsAt(lastPreflight.value, position);
const revisions = computed(() => targetRevisions(lastPreflight.value));
const span = computed(() => spanText(lastPreflight.value));

const steps = computed(() => [
  `Targets · ${targets.value.length}`,
  `Commands · ${stack.value.length}`,
  "GO / NO-GO",
  "Arm & uplink",
]);
const current = computed(() =>
  targets.value.length === 0
    ? 0
    : stack.value.length === 0 ||
        stack.value.some(
          (i) =>
            !checkItem(
              i,
              targets.value.map((t) => t.id),
            ).ok,
        )
      ? 1
      : blocked.value === null
        ? 3
        : 2,
);
/** A single explicit target names the request and is where close returns. */
const only = computed(() =>
  query.value.explicit.length === 1
    ? rows.value.find((sc) => sc.id === query.value.explicit[0])
    : undefined,
);
const context = computed(() => {
  const sc = only.value;
  const line = draftLine(saved.status.value);
  if (!sc) return `Uplink sequence · ${line}`;
  return line === "new"
    ? `Uplink sequence · for ${sc.name}`
    : `Uplink sequence · for ${sc.name} · ${line}`;
});
const close = computed((): RouteLocationRaw =>
  only.value
    ? { name: "ops.spacecraft", params: { scId: only.value.scid } }
    : { name: "ops.commands" },
);
</script>

<template>
  <TakeoverHeader
    title="New command request"
    :context="context"
    :close="close"
    :close-label="closeLabel(only?.name ?? 'Commands', saved.savedAt.value)"
    title-as="h1"
  >
    <template v-if="saved.savedAt.value !== null" #actions
      ><ApButton size="compact" variant="ghost" @click="discardAndClose"
        >Discard draft</ApButton
      ></template
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
        <DraftNotices
          :status="saved.status.value"
          :offered="saved.offered.value"
          :notice="saved.notice.value"
          @resume="saved.load"
          @discard-offered="discardOffered"
          @keep-mine="saved.keepMine"
          @retry="saved.retry"
        />
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
              :revisions="revisions"
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
            :groups-at="groupsAtStack"
            :name-of="nameOf"
            :span="span"
            :adding="adding"
            :targets="targets"
            @add="onAdd"
            @change="setValues"
            @per-target="setPerTarget"
            @move="(i, by) => (stack = move(stack, i, by))"
            @reorder="(from, to) => (stack = moveTo(stack, from, to))"
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
          :expires-at="release.expiresAt"
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
        :resolved="
          resolvedByCommand(lastPreflight?.commands, nameOf, (p) => stack[p]?.command.name ?? '')
        "
        :blocked="blocked"
        :submit="submission.state.value"
        @send="send"
        @check="check"
      />
    </div>
  </template>
  <ConfirmDialog
    ref="discardDialog"
    :question="
      discardAt ? `Discard the draft saved ${savedWhen(discardAt)}?` : 'Discard the draft?'
    "
    body="It can't be recovered."
    confirm="Discard draft"
    cancel="Cancel"
  />
  <ConfirmDialog
    ref="leaveDialog"
    question="Close without saving?"
    :body="
      saved.savedAt.value
        ? `Changes since ${savedWhen(saved.savedAt.value)} will be lost.`
        : 'Your changes will be lost.'
    "
    confirm="Close without saving"
    cancel="Stay"
  />
</template>
