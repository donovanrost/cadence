<script setup lang="ts">
import { computed, ref, shallowRef } from "vue";
import { describeApiError, isError } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApButton, ApCallout, ApDecision, ApPanel } from "@/ui";
import type { Preflight } from "../groups/api.ts";
import { goAcksToSend, goHoldReason, reviewHolds, type HoldAcks } from "../groups/checks.ts";
import HoldAckFields from "../compose/HoldAckFields.vue";
import { decide, type DecisionKind, type Group } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";
import RequestLogList from "./RequestLogList.vue";
import {
  cannotDecide,
  decisionErrorWords,
  decisionRecord,
  decisionOptions,
  flaggedTargets,
  membersChangedLine,
  noGoAfter,
} from "./decision.ts";

/**
 * D · Your call (CommandFlow C2). The server decides who may sign (awaiting_me, command.approve,
 * never your own); outcomes follow U20 — rejected says nothing changed, unclear says reload.
 */
const props = defineProps<{
  group: Group;
  review: Preflight | null;
  viewerId: string;
  canApprove: boolean;
  nameOf: PersonName;
  targetName: (spacecraftId: string) => string;
}>();
const emit = defineEmits<{ decided: [] }>();
const scope = useMissionScope();

const choice = ref<DecisionKind | null>(null);
const busy = ref(false);
type Outcome = { tone: "crit" | "caution"; text: string; reload: boolean } | null;
const outcome = shallowRef<Outcome>(null);
const flagged = computed(() => flaggedTargets(props.review, props.targetName));
const options = computed(() => decisionOptions(props.group, flagged.value));
/** #61: the approver's notes for review HOLDs the author's acks don't cover. */
const acks = ref<HoldAcks>({});
const holds = computed(() => reviewHolds(props.review, props.group.events));
const goKind = computed(() => choice.value === "go" || choice.value === "go_excluding");
/** U92: a GO refused because the group changed; GO stays off with it, NO-GO stays open. */
const membersChanged = ref<string | null>(null);
const blocked = computed(() => {
  const who = cannotDecide(props.group, props.viewerId, props.canApprove, props.nameOf);
  if (who) return who;
  if (goKind.value && membersChanged.value) return membersChanged.value;
  const noGo =
    choice.value === "go"
      ? noGoAfter(props.review, new Set())
      : choice.value === "go_excluding"
        ? noGoAfter(props.review, new Set(flagged.value.map((f) => f.spacecraftId)))
        : null;
  if (noGo) return noGo;
  return goKind.value
    ? goHoldReason(props.review, props.group.events, acks.value, props.targetName)
    : null;
});
/** ux §7 #15: a decided request shows its record and the log, not disabled options. */
const record = computed(() => decisionRecord(props.group, props.nameOf));

async function commit({ value, note }: { value: DecisionKind; note: string }) {
  busy.value = true;
  outcome.value = null;
  try {
    const result = await decide(scope.value.mission.id, props.group.id, {
      kind: value,
      excluded: value === "go_excluding" ? flagged.value.map((f) => f.spacecraftId) : [],
      note,
      expectedReview: props.group.review_token,
      acknowledgedHolds:
        value === "go" || value === "go_excluding"
          ? goAcksToSend(props.review, props.group.events, acks.value)
          : [],
    });
    if (result.status === "done") {
      choice.value = null;
      emit("decided");
    } else if (result.status === "rejected") {
      const e = result.error;
      if (isError(e, "command_group_members_changed")) {
        const line = membersChangedLine(e.kind === "conflict" ? e.details : undefined);
        membersChanged.value = line;
        outcome.value = { tone: "crit", text: line, reload: false };
        return;
      }
      outcome.value = {
        tone: "crit",
        text: `Not recorded. Nothing changed: ${decisionErrorWords(e)}`,
        reload: false,
      };
      if (
        isError(e, "command_group_review_stale") ||
        isError(e, "command_group_not_pending") ||
        isError(e, "holds_unacknowledged")
      )
        emit("decided");
    } else
      outcome.value = {
        tone: "caution",
        text: `It's unclear whether your decision was recorded (${describeApiError(result.error)}). Reload the request before deciding again.`,
        reload: true,
      };
  } finally {
    busy.value = false;
  }
}
const onCommit = (d: { value: DecisionKind; note: string }) =>
  commit(d).catch((e: unknown) => console.error("Decision failed", e));
</script>

<template>
  <ApPanel v-if="record" index="D" title="Decision" pane flush>
    <div class="flex flex-col gap-3 p-3">
      <ApCallout :tone="record.tone">{{ record.text }}</ApCallout>
      <div><RequestLogList :group="group" :name-of="nameOf" /></div>
    </div>
  </ApPanel>
  <ApPanel v-else index="D" title="Your call" pane flush>
    <!-- a11y B6 (#243): every outcome here is a refusal or an unclear decision: an alert. -->
    <ApCallout v-if="outcome" :tone="outcome.tone" role="alert">
      {{ outcome.text }}
      <template v-if="outcome.reload" #action
        ><ApButton size="compact" @click="emit('decided')">Reload</ApButton></template
      >
    </ApCallout>
    <HoldAckFields
      v-if="goKind"
      :holds="holds.open"
      :acks="acks"
      hint="The author's notes don't cover this HOLD as it stands now. Say why GO is safe; it goes in the request's log."
      @ack="(k, b, n) => (acks = { ...acks, [k]: { basis: b, note: n } })"
    />
    <ApDecision
      v-model="choice"
      :options="options"
      note-label="Note to the author"
      :busy="busy"
      :blocked-reason="blocked"
      caption="Abort stays open to both of you"
      @commit="onCommit"
    >
      <template #log>
        <RequestLogList :group="group" :name-of="nameOf" />
      </template>
    </ApDecision>
  </ApPanel>
</template>
