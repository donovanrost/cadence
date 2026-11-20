<script setup lang="ts">
import { computed, ref, shallowRef } from "vue";
import { describeApiError } from "@/api/index.ts";
import { useMissionScope, useSession } from "@/shell/index.ts";
import { useNow, ApButton, ApCallout, ApStatusMark } from "@/ui";
import {
  escalationNotice,
  runEpisodeCommand,
  sourceTag,
  statusLine,
  type CommandOutcome,
  type EpisodeCommand,
  type EpisodeDetail,
} from "@/features/alarms/index.ts";
import EpisodePersonForm from "./EpisodePersonForm.vue";

/**
 * The alarm's lifecycle beside its evidence (DECISIONS #6, ux U16/U20): status + source tag,
 * escalation notice, and Acknowledge / Assign / Hand off for viewers with the permission.
 * `layout="stacked"` (Mobile J6): full-width ≥48px Acknowledge | Hand off, no Assign.
 */
const props = withDefaults(
  defineProps<{
    episode: EpisodeDetail;
    permissions: readonly string[];
    layout?: "inline" | "stacked";
  }>(),
  { layout: "inline" },
);
const emit = defineEmits<{ changed: [] }>();
const scope = useMissionScope();
const now = useNow();
const stacked = computed(() => props.layout === "stacked");

const session = useSession();
const status = computed(() => statusLine(props.episode, session.user.id));
const escalation = computed(() => escalationNotice(props.episode));
const canAck = computed(
  () => props.permissions.includes("alarm.acknowledge") && props.episode.status === "new",
);
const canAssign = computed(
  () => props.permissions.includes("alarm.assign") && props.episode.status !== "cleared",
);

const form = ref<"assign" | "hand_off" | null>(null);
const busy = ref(false);
const outcome = shallowRef<CommandOutcome | null>(null);
async function run(command: EpisodeCommand) {
  busy.value = true;
  outcome.value = null;
  try {
    outcome.value = await runEpisodeCommand(scope.value.mission.id, props.episode.id, command);
    if (outcome.value.status === "done") {
      form.value = null;
      emit("changed");
    }
  } finally {
    busy.value = false;
  }
}
const act = (command: EpisodeCommand) => {
  run(command).catch((error: unknown) => console.error("Alarm command failed", error));
};
function submitForm(to: string | null, note: string) {
  if (form.value === "assign") act({ kind: "assign", userId: to, ...(note ? { note } : {}) });
  else if (form.value === "hand_off") act({ kind: "hand_off", to, note });
}
const toggle = (which: "assign" | "hand_off") => {
  form.value = form.value === which ? null : which;
};
const buttonSize = computed(() => (stacked.value ? "commit" : "compact"));
const buttonClass = computed(() => (stacked.value ? "min-h-12 w-full" : ""));
</script>

<template>
  <div class="flex flex-col gap-2 border-b border-hairline pb-3">
    <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
      <span
        class="inline-flex items-center gap-2 font-display text-md font-semibold tracking-tag uppercase text-readout"
      >
        <ApStatusMark :state="status.state" />{{ status.text }}
      </span>
      <span class="font-mono text-xs text-text-3 uppercase">{{ sourceTag(episode, now) }}</span>
      <span :class="stacked ? 'grid w-full grid-cols-2 gap-2' : 'ml-auto flex gap-2'">
        <ApButton
          v-if="canAck"
          :size="buttonSize"
          :class="buttonClass"
          variant="primary"
          :disabled="busy"
          disabled-reason="Working…"
          @click="act({ kind: 'acknowledge' })"
          >Acknowledge</ApButton
        >
        <ApButton
          v-if="canAssign && !stacked"
          :size="buttonSize"
          :class="buttonClass"
          :disabled="busy"
          disabled-reason="Working…"
          @click="toggle('assign')"
          :aria-expanded="form === 'assign'"
          >{{ form === "assign" ? "Cancel" : "Assign" }}</ApButton
        >
        <ApButton
          v-if="canAssign"
          :size="buttonSize"
          :class="buttonClass"
          :disabled="busy"
          disabled-reason="Working…"
          @click="toggle('hand_off')"
          :aria-expanded="form === 'hand_off'"
          >{{ form === "hand_off" ? "Cancel" : "Hand off" }}</ApButton
        >
      </span>
    </div>
    <ApCallout v-if="escalation" tone="caution">{{ escalation }}</ApCallout>
    <EpisodePersonForm
      v-if="form"
      :key="form"
      :mode="form"
      :busy="busy"
      :stacked="stacked"
      @submit="submitForm"
      @cancel="form = null"
    />
    <ApCallout v-if="outcome?.status === 'rejected'" tone="caution" role="alert">
      Nothing changed: {{ describeApiError(outcome.error) }}
    </ApCallout>
    <ApCallout v-else-if="outcome?.status === 'unclear'" tone="stale">
      It's unclear whether that went through ({{ describeApiError(outcome.error) }}). The status
      above updates when the server confirms; check it before trying again.
      <template #action
        ><ApButton size="compact" @click="emit('changed')">Check now</ApButton></template
      >
    </ApCallout>
  </div>
</template>
