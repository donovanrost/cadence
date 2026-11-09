<script setup lang="ts">
import { computed, ref, shallowRef } from "vue";
import { useRemoteQuery, describeApiError } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { useNow, ApButton, ApCallout, ApField, ApSelect, ApStatusMark } from "@/ui";
import {
  escalationNotice,
  fetchPeople,
  runEpisodeCommand,
  sourceTag,
  statusLine,
  type CommandOutcome,
  type EpisodeCommand,
  type EpisodeDetail,
} from "@/features/alarms/index.ts";

/**
 * The alarm's lifecycle beside its evidence (DECISIONS #6, ux U16/U20): status + source tag,
 * escalation notice, and Acknowledge / Assign for viewers with the permission.
 */
const props = defineProps<{ episode: EpisodeDetail; permissions: readonly string[] }>();
const emit = defineEmits<{ changed: [] }>();
const scope = useMissionScope();
const now = useNow();

const status = computed(() => statusLine(props.episode));
const escalation = computed(() => escalationNotice(props.episode));
const canAck = computed(
  () => props.permissions.includes("alarm.acknowledge") && props.episode.status === "new",
);
const canAssign = computed(
  () => props.permissions.includes("alarm.assign") && props.episode.status !== "cleared",
);

const busy = ref(false);
const outcome = shallowRef<CommandOutcome | null>(null);
async function run(command: EpisodeCommand) {
  busy.value = true;
  outcome.value = null;
  try {
    outcome.value = await runEpisodeCommand(scope.value.mission.id, props.episode.id, command);
    if (outcome.value.status === "done") {
      assigning.value = false;
      emit("changed");
    }
  } finally {
    busy.value = false;
  }
}
const act = (command: EpisodeCommand) => {
  run(command).catch((error: unknown) => console.error("Alarm command failed", error));
};

const assigning = ref(false);
const assignee = ref("");
const note = ref("");
const people = useRemoteQuery(
  computed(() => (assigning.value ? scope.value.organization.id : null)),
  (org, signal) => fetchPeople(org, signal),
);
const options = computed(() => [
  { value: "", label: "Choose a person…" },
  { value: "none", label: "Nobody (unassign)" },
  ...(people.state.value.status === "ready"
    ? people.state.value.value.members.map((m) => ({
        value: m.user_id,
        label: m.display_name ?? m.user_id,
      }))
    : []),
]);
function assign() {
  if (!assignee.value) return;
  act({
    kind: "assign",
    userId: assignee.value === "none" ? null : assignee.value,
    ...(note.value.trim() ? { note: note.value } : {}),
  });
}
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
      <span class="ml-auto flex gap-2">
        <ApButton
          v-if="canAck"
          size="compact"
          variant="primary"
          :disabled="busy"
          disabled-reason="Working…"
          @click="act({ kind: 'acknowledge' })"
          >Acknowledge</ApButton
        >
        <ApButton
          v-if="canAssign"
          size="compact"
          :disabled="busy"
          disabled-reason="Working…"
          @click="assigning = !assigning"
          >Assign</ApButton
        >
      </span>
    </div>
    <ApCallout v-if="escalation" tone="crit">{{ escalation }}</ApCallout>
    <form v-if="assigning" class="flex flex-wrap items-end gap-2" @submit.prevent="assign">
      <ApSelect v-model="assignee" label="Assign to" size="compact" :options="options" />
      <div class="min-w-[220px] flex-1"><ApField v-model="note" label="Note (optional)" /></div>
      <ApButton
        size="compact"
        type="submit"
        :disabled="!assignee || busy"
        disabled-reason="Choose a person first"
        >Assign</ApButton
      >
    </form>
    <ApCallout v-if="outcome?.status === 'rejected'" tone="caution">
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
