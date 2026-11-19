<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref, watch } from "vue";
import {
  formatClock,
  ApButton,
  ApCallout,
  ApEventLine,
  ApPanel,
  ApStatStrip,
  ApStatTile,
  ApStatusMark,
  ApTag,
  useNow,
} from "@/ui";
import { groupBlockedLine, recoverable } from "@/features/contacts/readiness.ts";
import { useStationCodes } from "@/features/contacts/useStationCodes.ts";
import RecoverUplink from "@/features/contacts/RecoverUplink.vue";
import type { Group } from "../groups/show.ts";
import {
  eventState,
  eventText,
  memberStageWord,
  STAGE_STATE,
  type PersonName,
} from "../groups/words.ts";
import { refusalLine, releaseLogContext, windowLine } from "../groups/release.ts";
import { ownValuesText } from "./ownValues.ts";
import { useCatalogArgs } from "./useCatalogArgs.ts";
import AbortPanel from "./AbortPanel.vue";
import ContactRelease from "./ContactRelease.vue";
import NeedsYouPanel from "./NeedsYouPanel.vue";
import TargetMatrix from "./TargetMatrix.vue";
import { useFleet } from "@/features/fleet/index.ts";
import VerifierPanel from "./VerifierPanel.vue";
import HistorySheet from "./HistorySheet.vue";
import { abortable, pipeline } from "./uplink.ts";
import { useVerifierSeries } from "./useVerifierSeries.ts";
import { targetVerifyTime } from "../groups/verifyTimes.ts";
import { expirySummary, targetStageWord } from "../groups/expiry.ts";

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
/** U1 matrix places targets by plane and slot from the fleet read. */
const fleet = useFleet(computed(() => props.missionId));
const fleetRows = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);
const series = useVerifierSeries(
  computed(() => props.missionId),
  computed(() => props.group.id),
);
const events = computed(() =>
  [...props.group.events].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)),
);
const decisionNote = computed(() => props.group.decision?.note ?? null);
const pos = (n: number) => String(n + 1).padStart(2, "0");
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
/** U46 (b): a member's latest named-release stop, under its target. */
const refusalOf = (t: Group["targets"][number]) => {
  const r = t.members.find((m) => m.release_refusal)?.release_refusal;
  return r ? refusalLine(r, { spacecraft: t.name }) : null;
};
/** ux C2: the commands this target sends with its own values, worded as Approve words them. */
const argsOf = useCatalogArgs(
  computed(() => props.missionId),
  computed(() => props.group),
);
const ownOf = (t: Group["targets"][number]) =>
  props.group.commands.flatMap((c) => {
    const values = ownValuesText(c, t.spacecraft_id, argsOf(c.command_id));
    return values === null ? [] : [{ position: c.position, name: c.name ?? c.command_id, values }];
  });
const release = computed(() =>
  releaseLogContext(
    props.group.uplink,
    props.group.targets.length === 1 ? (props.group.targets[0]?.name ?? null) : null,
  ),
);
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
    <NeedsYouPanel :group="group" :series="series.ready.value" @history="(t) => history?.open(t)" />
    <VerifierPanel
      :series="series"
      :mission-id="missionId"
      :group-id="group.id"
      :name-of="(id) => group.targets.find((t) => t.spacecraft_id === id)?.name ?? id"
    />
    <ApPanel index="U1" title="Targets" :meta="`${group.target_count}`" flush>
      <TargetMatrix :group="group" :fleet="fleetRows" />
      <ul class="m-0 list-none border-t border-hairline p-0">
        <li
          v-for="t in group.targets"
          :key="t.spacecraft_id"
          class="grid grid-cols-[14px_200px_minmax(0,1fr)_auto_auto] items-baseline gap-3 border-t border-hairline-faint px-4 py-2 first:border-t-0"
        >
          <ApStatusMark :state="STAGE_STATE[t.stage]" class="self-center" />
          <span class="font-mono text-md text-readout"
            >{{ t.name ?? "Unknown spacecraft" }}
            <span class="text-text-4">SCID {{ t.scid ?? "—" }}</span></span
          >
          <span class="min-w-0 truncate font-mono text-sm text-text-3">
            <template v-for="m in t.members" :key="m.request_id"
              >{{ pos(m.position) }} {{ m.command_name ?? m.command_id }} ·
              {{
                memberStageWord(
                  m.stage,
                  group.state,
                  m.end_reason,
                  t.name,
                  group.release?.expires_at ?? null,
                )
              }}&ensp;</template
            >
          </span>
          <ApTag :state="STAGE_STATE[t.stage]" :label="targetStageWord(t, group)" />
          <ApButton
            size="compact"
            variant="ghost"
            aria-haspopup="dialog"
            :aria-label="`History of ${t.name ?? 'this target'}`"
            @click="history?.open(t)"
            >History</ApButton
          >
          <!-- ux C2: a target with its own values shows them on its command line. -->
          <p
            v-for="o in ownOf(t)"
            :key="o.position"
            class="col-span-4 col-start-2 m-0 flex flex-wrap items-center gap-2 font-mono text-sm text-text-2"
          >
            {{ pos(o.position) }} {{ o.name }} {{ o.values }}
            <ApTag state="neutral" label="Own values" />
          </p>
          <!-- ux U69 A4a: verify by / verified at / timed out at, with seconds. -->
          <p
            v-if="targetVerifyTime(t)"
            class="col-span-4 col-start-2 m-0 font-mono text-sm text-text-3"
          >
            {{ targetVerifyTime(t) }}
          </p>
          <p v-if="refusalOf(t)" class="col-span-4 col-start-2 m-0 text-sm text-caution-text">
            {{ refusalOf(t) }}
          </p>
        </li>
      </ul>
    </ApPanel>
    <HistorySheet ref="history" :group="group" :mission-id="missionId" />
    <ApPanel index="U3" title="Request log" flush>
      <ol class="m-0 list-none p-0">
        <ApEventLine
          v-for="e in events"
          :key="e.id"
          :time="formatClock(new Date(e.at))"
          :datetime="e.at"
          :state="eventState(e)"
          mono
          >{{ eventText(e, nameOf, group.targets, release) }}</ApEventLine
        >
      </ol>
    </ApPanel>
  </div>
</template>
