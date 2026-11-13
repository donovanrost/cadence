<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { Scid } from "@/api/index.ts";
import { computed } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";
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
import AttentionBlock from "./AttentionBlock.vue";
import ProviderChangeBlock from "./ProviderChangeBlock.vue";
import PassChangeHistory from "./PassChangeHistory.vue";
import { attentionWords, changeEvidence, changeTitle } from "@/features/now/index.ts";
import { targetOfAttention } from "./attention.ts";
import SettlementBlock from "./SettlementBlock.vue";
import { noRecoverText, readinessTag, reasonKey, reasonLink, recoverable } from "./readiness.ts";
import RecoverUplink from "./RecoverUplink.vue";
import ReleasePass from "./ReleasePass.vue";
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
}>();
defineEmits<{ changed: [] }>();
const now = useNow();
/** The live provider change on this pass (its attention item), for the decision block. */
const liveChange = computed(() => {
  const a = props.pass?.attention;
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
  const a = props.pass?.attention;
  return a && a.source === "pass_release" ? attentionWords(a) : null;
});
// Recover is operate_mission, the same policy as abort (DECISIONS #42).
const access = useCommandAccess();
/** false only: null means no uplink leg was asked for (downlink only). */
const uplinkUnconfirmed = computed(() => props.pass?.uplink_confirmed === false);
/** K2: a rejected / failed reservation booked by a plan can be re-planned (lead, 4259c615). */
const replan = computed((): RouteLocationRaw | null => {
  const p = props.pass;
  return p?.plan && (p.state === "rejected" || p.state === "failed")
    ? { name: "ops.contacts.replan", query: { plan: p.plan.id } }
    : null;
});
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
      <SettlementBlock :mission-id="missionId" :pass-id="pass.id" />
      <AttentionBlock
        v-if="pass.attention && pass.attention.source === 'pass_resolution'"
        :mission-id="missionId"
        :attention="pass.attention"
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
        <ApTag v-if="uplinkUnconfirmed" state="caution" label="Uplink unconfirmed" />
        <ApTag v-if="pass.off_plan" state="neutral" label="Off-plan" />
      </div>
      <p v-if="pass.off_plan" class="m-0 text-sm text-text-2">
        {{ offPlanLine(pass.off_plan, now) }}
      </p>
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
          v-if="readiness.state === 'blocked' && !recoverable(readiness.reason)"
          class="m-0 text-sm text-text-2"
        >
          {{ noRecoverText(readiness.reason) }}
        </p>
        <RecoverUplink
          v-else-if="readiness.state === 'blocked'"
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
      <PassUplinks :mission-id="missionId" :pass-id="pass.id" />
      <ApButton v-if="replan" size="compact" :to="replan">Re-plan</ApButton>
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
