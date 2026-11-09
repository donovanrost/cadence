<script setup lang="ts">
import { computed, ref, shallowRef } from "vue";
import { describeApiError } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { formatClock, ApButton, ApCallout, ApDecision, ApEventLine, ApPanel } from "@/ui";
import type { Preflight } from "../groups/api.ts";
import { decide, type DecisionKind, type Group } from "../groups/show.ts";
import { eventText, type PersonName } from "../groups/words.ts";
import {
  cannotDecide,
  decisionErrorWords,
  decisionOptions,
  flaggedTargets,
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
const blocked = computed(() => {
  const who = cannotDecide(props.group, props.viewerId, props.canApprove, props.nameOf);
  if (who) return who;
  if (choice.value === "go") return noGoAfter(props.review, new Set());
  if (choice.value === "go_excluding")
    return noGoAfter(props.review, new Set(flagged.value.map((f) => f.spacecraftId)));
  return null;
});
const events = computed(() =>
  [...props.group.events].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)),
);

async function commit({ value, note }: { value: DecisionKind; note: string }) {
  busy.value = true;
  outcome.value = null;
  try {
    const result = await decide(scope.value.mission.id, props.group.id, {
      kind: value,
      excluded: value === "go_excluding" ? flagged.value.map((f) => f.spacecraftId) : [],
      note,
      expectedReview: props.group.review_token,
    });
    if (result.status === "done") {
      choice.value = null;
      emit("decided");
    } else if (result.status === "rejected") {
      const e = result.error;
      const code = "code" in e ? e.code : e.kind;
      outcome.value = {
        tone: "crit",
        text: `Not recorded. Nothing changed: ${decisionErrorWords(code, describeApiError(e))}`,
        reload: false,
      };
      if (code === "command_group_review_stale" || code === "command_group_not_pending")
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
  <ApPanel index="D" title="Your call" pane flush>
    <ApCallout v-if="outcome" :tone="outcome.tone">
      {{ outcome.text }}
      <template v-if="outcome.reload" #action
        ><ApButton size="compact" @click="emit('decided')">Reload</ApButton></template
      >
    </ApCallout>
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
        <p class="ap-label m-0 pb-1.5">Request log</p>
        <ol class="m-0 list-none p-0">
          <ApEventLine
            v-for="e in events"
            :key="e.id"
            :time="formatClock(new Date(e.at))"
            :datetime="e.at"
            state="neutral"
            >{{ eventText(e, nameOf) }}</ApEventLine
          >
        </ol>
      </template>
    </ApDecision>
  </ApPanel>
</template>
