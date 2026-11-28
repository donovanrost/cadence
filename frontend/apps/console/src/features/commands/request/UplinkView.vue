<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref, watch } from "vue";
import { ApButton, ApCallout, ApPanel, ApStatStrip, ApStatTile, useNow } from "@/ui";
import { groupBlockedLine, recoverable } from "@/features/contacts/readiness.ts";
import { useStationCodes } from "@/features/contacts/useStationCodes.ts";
import RecoverUplink from "@/features/contacts/RecoverUplink.vue";
import type { Group } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";
import { windowLine } from "../groups/release.ts";
import AbortPanel from "./AbortPanel.vue";
import ContactRelease from "./ContactRelease.vue";
import NeedsYouPanel from "./NeedsYouPanel.vue";
import RequestLogList from "./RequestLogList.vue";
import TargetsPanel from "./TargetsPanel.vue";
import VerifierPanel from "./VerifierPanel.vue";
import HistorySheet from "./HistorySheet.vue";
import { abortable, pipeline } from "./uplink.ts";
import { useVerifierSeries } from "./useVerifierSeries.ts";
import { expirySummary } from "../groups/expiry.ts";
import { withdrawnAfterGoLine } from "../groups/withdrawn.ts";

/**
 * C3 · Uplink & verify v1: pipeline tiles, each target's trail, the request log, and Abort
 * remaining, N Needs you and the U2 verifier plot (one M26 read for both). Waves come with #8.
 */
const props = defineProps<{
  group: Group;
  nameOf: PersonName;
  canAbort: boolean;
  /** Anyone who may request can resend a sent-back request (DECISIONS #31 (4)). */
  canResend: boolean;
  missionId: MissionId;
}>();
const emit = defineEmits<{ changed: [] }>();
/**
 * a11y B6/A5 (#243, ux #425): Abort's result, said from a status line that outlives AbortPanel (it
 * goes once the group can't abort). Focus follows only if it was in the panel when it went (B4).
 */
const aborted = ref("");
const abortEl = ref<HTMLElement | null>(null);
const abortedEl = ref<HTMLElement | null>(null);
const showAbort = computed(() => props.canAbort && abortable(props.group));
watch(
  showAbort,
  async (shown, was) => {
    if (shown || !was || !abortEl.value?.contains(document.activeElement)) return;
    await nextTick();
    abortedEl.value?.focus();
  },
  { flush: "pre" },
);
function onAborted(result: string) {
  aborted.value = result;
  emit("changed");
}
const tiles = computed(() => pipeline(props.group));
const series = useVerifierSeries(
  computed(() => props.missionId),
  computed(() => props.group.id),
);
const decisionNote = computed(() => props.group.decision?.note ?? null);
/** ux U70: a target's History sheet, opened from its line and its N card. */
const history = ref<InstanceType<typeof HistorySheet> | null>(null);
/** U33: the group's pass is blocked; the same line as the list, with expiry, above the trail. */
const stations = useStationCodes(computed(() => props.missionId));
const blocked = computed(() =>
  groupBlockedLine(props.group.uplink, props.group.release?.expires_at ?? null, stations),
);
/** U46 (a): the queued pass's command window from its times; the blocked line replaces it. */
const now = useNow();
const windowText = computed(() => {
  const pass = props.group.uplink?.pass;
  if (!pass || blocked.value || props.group.finished === true) return null;
  const line = windowLine(pass.starts_at, pass.ends_at, now.value);
  const code = pass.station.code ?? pass.station.name;
  return line && code ? `${code} pass · ${line}` : line;
});
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-auto">
    <ApCallout v-if="group.state === 'approval_pending'" tone="caution">
      Nothing radiates until a second operator gives the GO.
      <template v-if="group.awaiting_me" #action
        ><ApButton
          size="compact"
          :to="{ name: 'ops.commands.request', params: { requestId: group.id, view: 'review' } }"
          >Review</ApButton
        ></template
      >
    </ApCallout>
    <ApCallout v-else-if="group.state === 'sent_back' || group.state === 'rejected'" tone="off">
      {{ nameOf(group.decided_by?.user_id ?? null) }}
      {{ group.state === "sent_back" ? "sent it back" : "gave NO-GO"
      }}<template v-if="decisionNote">: “{{ decisionNote }}”</template>. Nothing radiated.
      <template v-if="group.state === 'sent_back' && canResend" #action
        ><ApButton
          size="compact"
          :to="{ name: 'ops.commands.new', query: { from: `group:${group.id}` } }"
          >Edit and resend</ApButton
        ></template
      >
    </ApCallout>
    <ApCallout v-else-if="group.state === 'aborted'" tone="off">
      Aborted by {{ nameOf(group.aborted_by?.user_id ?? null) }}: “{{ group.abort_reason }}”
    </ApCallout>
    <div v-if="blocked && group.uplink?.pass" class="flex flex-col gap-2">
      <ApCallout tone="crit">{{ blocked }}</ApCallout>
      <RecoverUplink
        v-if="recoverable(group.uplink.readiness?.reason ?? null)"
        :mission-id="missionId"
        :pass-id="group.uplink.pass.reservation_id"
        :recovering="false"
        :can-recover="canAbort"
        @changed="$emit('changed')"
      />
    </div>
    <p v-if="windowText" class="m-0 font-mono text-sm text-text-2">{{ windowText }}</p>
    <ContactRelease
      :group="group"
      :mission-id="missionId"
      :can-release="canAbort"
      @changed="$emit('changed')"
    />
    <!-- E2 (#546): an unattended release refuses these; a person naming the contact isn't refused. -->
    <ApCallout v-if="group.state === 'queued' && group.withdrawn_after_go" tone="caution">{{
      withdrawnAfterGoLine(group.withdrawn_after_go)
    }}</ApCallout>
    <!-- CommandFlow C3: Abort sits up top (header area), never below a long target list. -->
    <div v-if="showAbort" ref="abortEl"><AbortPanel :group="group" @done="onAborted" /></div>
    <p
      ref="abortedEl"
      role="status"
      tabindex="-1"
      :class="aborted ? 'm-0 text-md text-text-2' : 'sr-only'"
    >
      {{ aborted }}
    </p>
    <!-- ux U75: the request expired; its unsent uplinks all expired together. -->
    <p v-if="expirySummary(group)" class="m-0 text-md text-text-2">{{ expirySummary(group) }}</p>
    <ApStatStrip :columns="tiles.length" label="Uplink pipeline">
      <ApStatTile
        v-for="t in tiles"
        :key="t.key"
        :label="t.label"
        :value="t.value"
        :share="group.target_count ? t.value / group.target_count : 0"
        :state="t.value ? t.state : undefined"
      />
    </ApStatStrip>
    <NeedsYouPanel
      :group="group"
      :series="series.ready.value"
      :mission-id="missionId"
      @history="(t) => history?.open(t)"
    />
    <VerifierPanel
      :series="series"
      :mission-id="missionId"
      :group-id="group.id"
      :name-of="
        (id) => group.targets.find((t) => t.spacecraft_id === id)?.name ?? 'Unknown spacecraft'
      "
    />
    <TargetsPanel :group="group" :mission-id="missionId" @history="(t) => history?.open(t)" />
    <HistorySheet ref="history" :group="group" :mission-id="missionId" />
    <ApPanel index="U3" title="Request log" flush>
      <RequestLogList :group="group" :name-of="nameOf" :mission-id="missionId" marked />
    </ApPanel>
  </div>
</template>
