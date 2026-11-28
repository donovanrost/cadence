<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, useId } from "vue";
import { describeApiError } from "@/api/index.ts";
import { useSession } from "@/shell/index.ts";
import { ApButton, ApCallout, ApPanel, ApSheet, ApTextarea, OutcomeCallout, useNow } from "@/ui";
import {
  decide,
  decisionErrorWords,
  namelessTargets,
  phoneGoBlocked,
  useCommandAccess,
  usePeopleNames,
  useYourGo,
  yourGoWords,
} from "@/features/commands/index.ts";

/**
 * Mobile.md §3 "Your GO is requested": shown only when a request awaiting your GO targets this
 * spacecraft. GO opens a confirm sheet restating targets and commands; NO-GO asks for the note.
 * A HOLD needing your note, or a NO-GO in the re-check, sends you to the full review (DECISIONS #7:
 * a GO from the phone is a second GO like any other).
 */
const props = defineProps<{ missionId: MissionId; spacecraftId: string }>();
const session = useSession();
const access = useCommandAccess();
const nameOf = usePeopleNames();
const now = useNow();
const go = useYourGo(
  computed(() => props.missionId),
  computed(() => props.spacecraftId),
);
const group = computed(() => go.group.value);
const reviewValue = computed(() =>
  go.review.state.value.status === "ready" ? go.review.state.value.value : null,
);
const holdsValue = computed(() =>
  go.holds.state.value.status === "ready" ? go.holds.state.value.value : null,
);
const words = computed(() => (group.value ? yourGoWords(group.value, nameOf, now.value) : null));
const blocked = computed(() =>
  group.value
    ? phoneGoBlocked(
        group.value,
        reviewValue.value,
        holdsValue.value,
        session.user.id,
        access.value.approve,
        nameOf,
      )
    : null,
);
const goSheet = ref<InstanceType<typeof ApSheet> | null>(null);
const noGoSheet = ref<InstanceType<typeof ApSheet> | null>(null);
const note = ref("");
const noteError = ref<string | null>(null);
// ux a11y A1 exception: the NO-GO sheet opens on the note, so its consequence describes the dialog.
const noGoConsequence = useId();
const busy = ref(false);
const outcome = ref<{ tone: "info" | "crit" | "caution"; text: string } | null>(null);
const targetNames = computed(() => {
  const names = (group.value?.targets ?? []).map((t) => t.name ?? "Unknown spacecraft");
  return names.length > 8
    ? `${names.slice(0, 8).join(", ")} and ${names.length - 8} more`
    : names.join(", ");
});
/** ux #237: a target without a name doesn't block GO; its id stays in Technical details. */
const nameless = computed(() => (group.value ? namelessTargets(group.value) : null));

async function sign(kind: "go" | "no_go") {
  const g = group.value;
  if (!g || busy.value) return;
  if (kind === "no_go" && !note.value.trim()) {
    noteError.value = "Say why: it goes to the author and the log.";
    return;
  }
  busy.value = true;
  outcome.value = null;
  try {
    const r = await decide(props.missionId, g.id, {
      kind,
      excluded: [],
      note: kind === "no_go" ? note.value.trim() : "",
      expectedReview: g.review_token,
      acknowledgedHolds: [],
    });
    goSheet.value?.close();
    noGoSheet.value?.close();
    if (r.status === "done")
      outcome.value = { tone: "info", text: kind === "go" ? "GO signed." : "NO-GO signed." };
    else if (r.status === "rejected") {
      const e = r.error;
      outcome.value = {
        tone: "crit",
        text: `Not recorded. Nothing changed: ${decisionErrorWords(e)}`,
      };
    } else
      outcome.value = {
        tone: "caution",
        text: `It's unclear whether your decision was recorded (${describeApiError(r.error)}). Check the request before deciding again.`,
      };
    go.refetch();
  } finally {
    busy.value = false;
  }
}
const run = (kind: "go" | "no_go") =>
  sign(kind).catch((e: unknown) => console.error("Decision failed", e));
function openNoGo() {
  note.value = "";
  noteError.value = null;
  noGoSheet.value?.open();
}
</script>

<template>
  <OutcomeCallout v-if="outcome && !group" :outcome="outcome" />
  <ApPanel v-if="group && words" index="G" title="Your GO is requested" alert="caution">
    <div class="flex flex-col gap-2">
      <p class="m-0 font-display text-lg font-semibold">{{ words.title }}</p>
      <p class="m-0 font-mono text-sm text-text-3">{{ words.by }}</p>
      <p class="m-0 text-text-2">{{ words.release }}</p>
      <ol class="m-0 list-none p-0 font-mono text-sm text-readout">
        <li v-for="line in words.stack" :key="line" class="truncate">{{ line }}</li>
      </ol>
      <OutcomeCallout v-if="outcome" :outcome="outcome" />
      <p v-if="blocked" class="m-0 text-sm text-caution-text">{{ blocked }}</p>
      <ApCallout v-if="nameless" tone="caution">
        {{ nameless.line }}
        <details class="mt-1 text-xs text-text-3">
          <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
          <p v-for="id in nameless.ids" :key="id" class="m-0 font-mono">{{ id }}</p>
        </details>
      </ApCallout>
      <div class="grid grid-cols-2 gap-2 pt-1">
        <ApButton v-if="!blocked" class="min-h-12" :disabled="busy" @click="goSheet?.open()"
          >GO</ApButton
        >
        <ApButton
          v-else
          class="min-h-12"
          variant="secondary"
          :to="{ name: 'ops.commands.request', params: { requestId: group.id, view: 'review' } }"
          >Open review</ApButton
        >
        <ApButton
          class="min-h-12"
          variant="secondary"
          :disabled="busy || !access.approve"
          @click="openNoGo"
          >NO-GO</ApButton
        >
      </div>
    </div>
    <ApSheet ref="goSheet" :title="words.confirm">
      <p class="m-0 text-text-2">Targets: {{ targetNames }}.</p>
      <ol class="m-0 list-none p-0 font-mono text-sm text-readout">
        <li v-for="line in words.stack" :key="line">{{ line }}</li>
      </ol>
      <template #footer>
        <ApButton variant="ghost" class="min-h-12" @click="goSheet?.close()">Cancel</ApButton>
        <ApButton class="min-h-12" :disabled="busy" @click="run('go')">Sign GO</ApButton>
      </template>
    </ApSheet>
    <ApSheet ref="noGoSheet" title="NO-GO" initial-focus="textarea" :described-by="noGoConsequence">
      <p :id="noGoConsequence" class="m-0 text-base text-text-3">
        A NO-GO closes this request: nothing is sent, and the author sees your note.
      </p>
      <ApTextarea v-model="note" label="Note to the author" required :error="noteError" :rows="3" />
      <template #footer>
        <ApButton variant="ghost" class="min-h-12" @click="noGoSheet?.close()">Cancel</ApButton>
        <ApButton variant="danger" class="min-h-12" :disabled="busy" @click="run('no_go')"
          >Sign NO-GO</ApButton
        >
      </template>
    </ApSheet>
  </ApPanel>
</template>
