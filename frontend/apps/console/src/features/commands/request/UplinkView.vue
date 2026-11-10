<script setup lang="ts">
import { computed } from "vue";
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
import AbortPanel from "./AbortPanel.vue";
import { abortable, pipeline } from "./uplink.ts";

/**
 * C3 · Uplink & verify v1: pipeline tiles, each target's trail, the request log, and Abort
 * remaining. Waves, the verifier plot and Needs-you cards come with their data (#8, M24).
 */
const props = defineProps<{
  group: Group;
  nameOf: PersonName;
  canAbort: boolean;
  /** Anyone who may request can resend a sent-back request (DECISIONS #31 (4)). */
  canResend: boolean;
  missionId: string;
}>();
defineEmits<{ changed: [] }>();
const tiles = computed(() => pipeline(props.group));
const events = computed(() =>
  [...props.group.events].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)),
);
const decisionNote = computed(() => props.group.decision?.note ?? null);
const pos = (n: number) => String(n + 1).padStart(2, "0");
/** U33: the group's pass is blocked; the same line as the list, with expiry, above the trail. */
const codeOf = useStationCodes(computed(() => props.missionId));
const blocked = computed(() =>
  groupBlockedLine(props.group.uplink, props.group.release?.expires_at ?? null, codeOf),
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
    <div v-if="blocked && group.uplink" class="flex flex-col gap-2">
      <ApCallout tone="crit">{{ blocked }}</ApCallout>
      <RecoverUplink
        v-if="recoverable(group.uplink.readiness.reason)"
        :mission-id="missionId"
        :pass-id="group.uplink.pass.reservation_id"
        :recovering="false"
        :can-recover="canAbort"
        @changed="$emit('changed')"
      />
    </div>
    <!-- CommandFlow C3: Abort sits up top (header area), never below a long target list. -->
    <AbortPanel v-if="canAbort && abortable(group)" :group="group" @done="$emit('changed')" />
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
    <ApPanel index="U1" title="Targets" :meta="`${group.target_count}`" flush>
      <ul class="m-0 list-none p-0">
        <li
          v-for="t in group.targets"
          :key="t.spacecraft_id"
          class="grid grid-cols-[14px_200px_minmax(0,1fr)_auto] items-baseline gap-3 border-t border-hairline-faint px-4 py-2 first:border-t-0"
        >
          <ApStatusMark :state="STAGE_STATE[t.stage]" class="self-center" />
          <span class="font-mono text-md text-readout"
            >{{ t.name ?? "Unknown spacecraft" }}
            <span class="text-text-4">SCID {{ t.scid ?? "—" }}</span></span
          >
          <span class="min-w-0 truncate font-mono text-sm text-text-3">
            <template v-for="m in t.members" :key="m.request_id"
              >{{ pos(m.position) }} {{ m.command_name ?? m.command_id }} ·
              {{ memberStageWord(m.stage, group.state) }}&ensp;</template
            >
          </span>
          <ApTag :state="STAGE_STATE[t.stage]" :label="memberStageWord(t.stage, group.state)" />
        </li>
      </ul>
    </ApPanel>
    <ApPanel index="U3" title="Request log" flush>
      <ol class="m-0 list-none p-0">
        <ApEventLine
          v-for="e in events"
          :key="e.id"
          :time="formatClock(new Date(e.at))"
          :datetime="e.at"
          :state="eventState(e)"
          mono
          >{{ eventText(e, nameOf, group.targets) }}</ApEventLine
        >
      </ol>
    </ApPanel>
  </div>
</template>
