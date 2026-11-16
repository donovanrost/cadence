<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { Scid } from "@/api/index.ts";
import { computed } from "vue";
import { RouterLink } from "vue-router";
import {
  formatClock,
  formatCountdown,
  formatDuration,
  useNow,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApKeyValue,
  ApPanel,
  ApStateTrail,
  ApTag,
} from "@/ui";
import {
  contactOpState,
  contactState,
  contactStateWord,
  sourceLabel,
} from "@/features/scheduling/index.ts";
import type { Pass } from "./api.ts";
import { replanLink } from "./replanLink.ts";
import AttentionBlock from "./AttentionBlock.vue";
import ProviderChangeBlock from "./ProviderChangeBlock.vue";
import PassChangeHistory from "./PassChangeHistory.vue";
import {
  attentionWords,
  changeEvidence,
  changeTitle,
  type attentionSources,
} from "@/features/now/index.ts";
import { targetOfAttention } from "./attention.ts";
import SettlementBlock from "./SettlementBlock.vue";
import CutOffNote from "./CutOffNote.vue";
import ContactStartBlock from "./ContactStartBlock.vue";
import ArchiveBlock from "./ArchiveBlock.vue";
import IngressBlock from "./IngressBlock.vue";
import JobBlock from "./JobBlock.vue";
import ListenerBlock from "./ListenerBlock.vue";
import PassTechnical from "./PassTechnical.vue";
import BookedRow from "./BookedRow.vue";
import ReservationRecord from "./ReservationRecord.vue";
import { passAttentions, passAttentionTag } from "./passAttention.ts";
import { noRecoverText, readinessTag, reasonKey, reasonLink, recoverable } from "./readiness.ts";
import RecoverUplink from "./RecoverUplink.vue";
import ReleasePass from "./ReleasePass.vue";
import ContactEndAction from "./ContactEndAction.vue";
import { endedCode, endedLine, endedTag } from "./contactEnd.ts";
import PassUplinks from "./PassUplinks.vue";
import { contactTrail } from "./trail.ts";
import { offPlanLine } from "./singleBookings.ts";
import { useCommandAccess } from "@/features/commands/index.ts";
import { stationLabel } from "./gantt.ts";

/**
 * D2 · Selected pass (Contacts.md): spacecraft + state, station and countdown, window, duration,
 * source, the contact's state trail and the requests queued on it. Max elevation, sky plot and
 * downlink estimates are omitted (no propagation, DECISIONS #4); Swap station is out (#68).
 */
const props = defineProps<{
  missionId: MissionId;
  pass: Pass | null;
  spacecraft: { name: string; scid: Scid | null } | null;
  /** The pass named in the URL is still being read (qa: never "No pass selected" meanwhile). */
  loading?: boolean;
  /** The pass named in the URL couldn't be read (gone, or not this mission's). */
  missing?: boolean;
  /** The pass named in the URL couldn't be read for another reason (Try again emits changed). */
  failed?: boolean;
}>();
defineEmits<{ changed: [] }>();
const now = useNow();
/** The live provider change on this pass (its attention item), for the decision block. */
/** U45: every open item on the pass, top first; each block finds its own. */
const items = computed(() => (props.pass ? passAttentions(props.pass) : []));
const itemOf = (source: (typeof attentionSources)[number]) =>
  items.value.find((a) => a.source === source) ?? null;
const startItem = computed(() => itemOf("contact_start"));
/** U47: a pass can have both a backlog and lost frames. */
const ingressItems = computed(() => items.value.filter((a) => a.source === "ingress_backpressure"));
const archiveItems = computed(() => items.value.filter((a) => a.source === "archive_quarantine"));
const listenerItem = computed(() => itemOf("listener_refusal"));
const jobItems = computed(() => items.value.filter((a) => a.source === "job_outcome_unknown"));
const attentionTag = computed(() => (props.pass ? passAttentionTag(props.pass) : null));
const resolutionItem = computed(() => itemOf("pass_resolution"));
const liveChange = computed(() => {
  const a = itemOf("provider_change");
  // An expired change (its pass ended undecided) has no decision; the history shows it (U44).
  if (!a || a.source !== "provider_change" || a.provider_change?.state === "expired") return null;
  const c = a.conflict;
  const conflict =
    c === "approval_required" || c === "acknowledgment_required" || c === "configuration_failure"
      ? c
      : null;
  if (conflict === null) return null;
  return {
    target: targetOfAttention(a),
    conflict,
    fields: a.provider_change?.fields ?? [],
    title: `${changeTitle(a, now.value)}.`,
    evidence: changeEvidence(a, now.value),
  };
});

const state = computed(() => (props.pass ? contactState(props.pass) : null));
/** U32: an attested pass says whose word it rests on, not the provider's. */
const tag = computed(() => {
  if (state.value === null) return null;
  const p = props.pass;
  // U55: once Cadence's side stopped, the tag says so (the booking itself is unchanged).
  const ended = endedTag(p?.contact_ended);
  if (ended) return ended;
  const label =
    p?.booking_evidence === "operator_attested"
      ? `Booked · attested by ${p.attested_by?.name ?? "an operator"}`
      : contactStateWord[state.value];
  return { state: contactOpState(state.value), label };
});
/** U33: readiness in the drawer ("Uplink ready" too); Recover while blocked or recovering. */
const readiness = computed(() => {
  const r = props.pass?.uplink_readiness;
  const p = props.pass;
  if (!r || !p) return null;
  const tag = readinessTag(r, "drawer", { provider: p.source.provider_name, los: p.ends_at });
  return { ...r, tag, link: reasonLink(r.reason) };
});
const releaseIssue = computed(() => {
  const a = itemOf("pass_release");
  return a ? attentionWords(a) : null;
});
// Recover is operate_mission, the same policy as abort (DECISIONS #42).
const access = useCommandAccess();
/** false only: null means no uplink leg was asked for (downlink only). */
const uplinkUnconfirmed = computed(() => props.pass?.uplink_confirmed === false);
const replan = computed(() => replanLink(props.pass, now.value.getTime()));
const facts = computed(() => {
  const p = props.pass;
  if (!p) return [];
  const from = new Date(p.starts_at);
  const to = new Date(p.ends_at);
  return [
    {
      key: "window",
      label: "Window",
      // A pass opened from Now can be days out (U31): name its day unless it's today (UTC).
      value: `${p.starts_at.slice(0, 10) === now.value.toISOString().slice(0, 10) ? "" : `${p.starts_at.slice(5, 10)} `}${formatClock(from)} – ${formatClock(to)}Z`,
      mono: true,
    },
    {
      key: "duration",
      label: "Duration",
      value: formatDuration((to.getTime() - from.getTime()) / 1000),
      mono: true,
    },
    ...(p.max_elevation_deg === null
      ? []
      : [{ key: "el", label: "Max el", value: `${p.max_elevation_deg}°`, mono: true }]),
    ...(p.uplink_capable === null
      ? []
      : [
          {
            key: "link",
            label: "Link",
            value: p.uplink_capable ? "Uplink capable" : "Downlink only",
          },
        ]),
    { key: "source", label: "Source", value: sourceLabel(p.source, "contact") },
    { key: "station", label: "Station", value: p.station.name ?? stationLabel(p) },
  ];
});
const countdown = computed(() => {
  const p = props.pass;
  if (!p) return "";
  const aos = Date.parse(p.starts_at);
  return aos > now.value.getTime()
    ? `AOS ${formatCountdown(new Date(aos), now.value)}`
    : `LOS ${formatCountdown(new Date(p.ends_at), now.value)}`;
});
</script>

<template>
  <ApPanel index="D2" title="Selected pass" pane flush>
    <p v-if="!pass && loading" role="status" class="m-0 p-4 font-mono text-xs text-text-4">
      LOADING PASS…
    </p>
    <ApEmptyState
      v-else-if="!pass && missing"
      headline="Pass not found"
      sentence="It isn't on this mission's schedule any more. Choose a bar in the schedule."
    />
    <ApEmptyState v-else-if="!pass && failed" headline="This pass couldn't load.">
      <ApButton size="compact" @click="$emit('changed')">Try again</ApButton>
    </ApEmptyState>
    <ApEmptyState
      v-else-if="!pass"
      headline="No pass selected"
      sentence="Choose a bar in the schedule."
    />
    <div v-else class="flex flex-col gap-3 p-4">
      <!-- pass_release (1a87609e): no acknowledge; it stays open until the booking settles. -->
      <ApCallout v-if="releaseIssue" tone="caution">
        <p class="m-0 font-semibold">{{ releaseIssue.what }}</p>
        <p class="m-0 text-text-2">{{ releaseIssue.evidence }}</p>
      </ApCallout>
      <!-- U45: a pass that failed to start, or was missed. -->
      <ContactStartBlock
        v-if="startItem"
        :key="startItem.id"
        :mission-id="missionId"
        :attention="startItem"
        :now="now"
        @changed="$emit('changed')"
      />
      <!-- U47: this pass's telemetry backing up, or frames lost. -->
      <IngressBlock
        v-for="a in ingressItems"
        :key="a.id"
        :mission-id="missionId"
        :attention="a"
        @changed="$emit('changed')"
      />
      <!-- U54: a job for this pass whose outcome is unknown. -->
      <JobBlock
        v-for="a in jobItems"
        :key="a.id"
        :mission-id="missionId"
        :attention="a"
        :now="now"
        @changed="$emit('changed')"
      />
      <!-- U50: connections this pass's shared listener refused. -->
      <ListenerBlock
        v-if="listenerItem"
        :attention="listenerItem"
        :spacecraft="spacecraft?.name ?? null"
        :now="now"
      />
      <!-- U49: raw records from this pass the archive couldn't take. -->
      <ArchiveBlock
        v-for="a in archiveItems"
        :key="a.id"
        :mission-id="missionId"
        :attention="a"
        :now="now"
        @changed="$emit('changed')"
      />
      <SettlementBlock :mission-id="missionId" :pass-id="pass.id" />
      <CutOffNote :cut-off="pass.incomplete_at_end" />
      <AttentionBlock
        v-if="resolutionItem"
        :mission-id="missionId"
        :attention="resolutionItem"
        @changed="$emit('changed')"
      />
      <!-- §11 L14 (ux U44): a provider's change to this pass, decided here. -->
      <ProviderChangeBlock
        v-if="liveChange"
        :key="liveChange.target.id"
        :mission-id="missionId"
        :target="liveChange.target"
        :conflict="liveChange.conflict"
        :fields="liveChange.fields"
        :title="liveChange.title"
        :evidence="liveChange.evidence"
        :now="now"
        @changed="$emit('changed')"
      />
      <!-- ux U44 pass history (api, L14 flown passes): every change and its outcome. -->
      <PassChangeHistory
        :mission-id="missionId"
        :pass-id="pass.id"
        :provider="pass.source.provider_name ?? null"
        :live-change-id="liveChange?.target.id ?? null"
        :now="now"
        @changed="$emit('changed')"
      />
      <div class="flex flex-wrap items-center gap-3">
        <RouterLink
          v-if="spacecraft && spacecraft.scid !== null"
          :to="{ name: 'ops.spacecraft', params: { scId: spacecraft.scid } }"
          class="max-md:hit-44 font-display text-lg font-semibold text-readout no-underline hover:underline"
          >{{ spacecraft.name }}</RouterLink
        >
        <span v-else-if="spacecraft" class="font-display text-lg font-semibold text-readout">{{
          spacecraft.name
        }}</span>
        <ApTag v-if="tag" :state="tag.state" :label="tag.label" />
        <!-- U45: the top attention item, the rest counted beside it. -->
        <template v-if="attentionTag">
          <ApTag :state="attentionTag.state" :label="attentionTag.label" />
          <span v-if="attentionTag.more" class="font-mono text-sm text-text-3"
            >+{{ attentionTag.more }}</span
          >
        </template>
        <ApTag v-if="uplinkUnconfirmed" state="caution" label="Uplink unconfirmed" />
        <ApTag v-if="pass.off_plan" state="neutral" label="Off-plan" />
      </div>
      <p v-if="pass.off_plan" class="m-0 text-sm text-text-2">
        {{ offPlanLine(pass.off_plan, now) }}
      </p>
      <BookedRow v-else :mission-id="missionId" :pass="pass" />
      <p v-if="pass.contact_ended" class="m-0 text-sm text-text-2">
        {{ endedLine(pass.contact_ended, pass.source.provider_name, now) }}
      </p>
      <!-- U56: a provider's reason code is worded or left out; the raw key lives here. -->
      <details v-if="endedCode(pass.contact_ended)" class="text-xs text-text-3">
        <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
        <p class="m-0 pt-1 font-mono">reason: {{ endedCode(pass.contact_ended) }}</p>
      </details>
      <p class="m-0 font-mono text-md text-text-2 uppercase">
        {{ pass.station.name ?? stationLabel(pass) }} ·
        <span class="text-readout">{{ countdown }}</span>
      </p>
      <div v-if="readiness?.tag" class="flex flex-col gap-2">
        <div class="flex flex-wrap items-center gap-2">
          <ApTag :state="readiness.tag.state" :label="readiness.tag.label" />
          <span v-if="readiness.tag.sentence" class="text-sm text-text-2">{{
            readiness.tag.sentence
          }}</span>
          <RouterLink
            v-if="readiness.link"
            :to="readiness.link.to"
            class="max-md:hit-44 text-sm text-readout underline hover:text-bright"
            >{{ readiness.link.label }}</RouterLink
          >
        </div>
        <p
          v-if="
            readiness.state === 'blocked' &&
            !recoverable(readiness.reason) &&
            noRecoverText(readiness.reason)
          "
          class="m-0 text-sm text-text-2"
        >
          {{ noRecoverText(readiness.reason) }}
        </p>
        <RecoverUplink
          v-else-if="readiness.state === 'blocked' && recoverable(readiness.reason)"
          :mission-id="missionId"
          :pass-id="pass.id"
          :recovering="false"
          :can-recover="access.abort"
          @changed="$emit('changed')"
        />
        <!-- U33 amendment 2: the raw key lives here only, never in the copy. -->
        <details v-if="readiness.reason" class="text-xs text-text-3">
          <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
          <p class="m-0 pt-1 font-mono">reason: {{ reasonKey(readiness.reason) }}</p>
        </details>
      </div>
      <ApStateTrail v-if="state" :steps="contactTrail(state)" label="Contact state" />
      <ApKeyValue :items="facts" />
      <PassTechnical :mission-id="missionId" :pass-id="pass.id" />
      <ReservationRecord
        :mission-id="missionId"
        :pass-id="pass.id"
        :provider-name="pass.source.provider_name"
      />
      <PassUplinks :mission-id="missionId" :pass-id="pass.id" />
      <ApButton v-if="replan" size="compact" :to="replan">Re-plan</ApButton>
      <ContactEndAction
        :mission-id="missionId"
        :pass="pass"
        :spacecraft="spacecraft?.name ?? pass.spacecraft?.name ?? 'Unknown spacecraft'"
        :now="now"
        @changed="$emit('changed')"
      />
      <ReleasePass
        :mission-id="missionId"
        :pass="pass"
        :spacecraft="spacecraft?.name ?? pass.spacecraft?.name ?? 'Unknown spacecraft'"
        :now="now"
        @changed="$emit('changed')"
      />
    </div>
  </ApPanel>
</template>
