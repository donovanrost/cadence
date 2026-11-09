<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  plural,
  ApButton,
  ApCallout,
  ApOption,
  ApPanel,
  ApSelect,
  ApStatStrip,
  ApStatTile,
  ApTextarea,
  ApTimePicker,
} from "@/ui";
import { fetchPeople } from "@/features/alarms/index.ts";

/**
 * C5 · Sequence summary: counts, release, second GO (DECISIONS #7/#31), log entry, commit. The
 * commit stays disabled with its reason until group requests (M16) exist; nothing radiates
 * without a GO.
 */
export type Release = { mode: "next_contact" | "not_before"; notBefore: number | null };
const props = defineProps<{
  targets: number;
  commands: number;
  secondGo: readonly string[];
  blocked: string | null;
}>();
const release = defineModel<Release>("release", { required: true });
const approver = defineModel<string>("approver", { required: true });
const log = defineModel<string>("log", { required: true });
const scope = useMissionScope();

const people = useRemoteQuery(
  computed(() => (props.secondGo.length ? scope.value.organization.id : null)),
  (org, signal) => fetchPeople(org, signal),
);
const approvers = computed(() => [
  { value: "", label: "Any operator on shift" },
  ...(people.state.value.status === "ready"
    ? people.state.value.value.members
        .filter((m) => m.capabilities.includes("command.approve"))
        .map((m) => ({ value: m.user_id, label: m.display_name ?? m.user_id }))
    : []),
]);
const uplinks = computed(() => props.targets * props.commands);
const mode = computed({
  get: () => release.value.mode,
  set: (m: Release["mode"] | null) => {
    if (m) release.value = { ...release.value, mode: m };
  },
});
const notBefore = computed({
  get: () => release.value.notBefore,
  set: (t: number | null) => (release.value = { ...release.value, notBefore: t }),
});
</script>

<template>
  <ApPanel index="C5" title="Sequence summary" pane flush>
    <div class="flex flex-col gap-4 p-4">
      <ApStatStrip :columns="3" label="Sequence size">
        <ApStatTile label="Targets" :value="targets" />
        <ApStatTile label="Cmds" :value="commands" />
        <ApStatTile label="Uplinks" :value="uplinks" />
      </ApStatStrip>
      <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
        <legend class="ap-label pb-2">Release</legend>
        <ApOption
          v-model="mode"
          name="release"
          value="next_contact"
          title="At each target's next AOS"
          description="Recommended. Each uplink waits for its own target's contact."
        />
        <ApOption
          v-model="mode"
          name="release"
          value="not_before"
          title="Hold until a set time"
          description="Then the first AOS after it."
        />
        <ApTimePicker
          v-if="mode === 'not_before'"
          v-model="notBefore"
          label="Not before"
          future
          past-message="That time has passed; the release would go at the next AOS."
        />
      </fieldset>
      <div v-if="secondGo.length" class="flex flex-col gap-2">
        <ApCallout tone="caution">Needs a second GO: {{ secondGo.join("; ") }}.</ApCallout>
        <ApSelect v-model="approver" label="Second GO from" size="compact" :options="approvers" />
      </div>
      <ApTextarea
        v-model="log"
        label="Log entry"
        :rows="3"
        :required="secondGo.length > 0"
        placeholder="Why this sequence, for the request log"
      />
      <ApButton
        variant="primary"
        size="commit"
        class="w-full"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? ''"
      >
        {{
          secondGo.length
            ? `Request GO · ${plural(uplinks, "uplink")}`
            : `Arm ${plural(uplinks, "uplink")}`
        }}
      </ApButton>
      <p v-if="blocked" class="m-0 text-md text-text-3">{{ blocked }}</p>
      <p class="m-0 font-mono text-xs text-text-4 uppercase">Nothing radiates without a GO</p>
    </div>
  </ApPanel>
</template>
