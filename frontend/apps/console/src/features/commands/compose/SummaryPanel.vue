<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  plural,
  ApButton,
  ApCallout,
  ApField,
  ApPanel,
  ApSelect,
  ApStatStrip,
  ApStatTile,
  ApTextarea,
} from "@/ui";
import { fetchPeople } from "@/features/alarms/index.ts";
import type { Release } from "./draft.ts";
import type { ResolvedCommand } from "../groups/resolved.ts";
import { expiresWords } from "../priority.ts";
import ReleaseFields from "./ReleaseFields.vue";
import SubmitOutcome from "./SubmitOutcome.vue";
import type { SubmitState } from "./useSubmit.ts";

/**
 * C5 · Sequence summary: counts, release, second GO (DECISIONS #7/#31), title, log entry, commit.
 * The commit is disabled with its reason until the server's checks answer this exact draft with no
 * NO-GO; nothing radiates without a GO.
 */
const props = defineProps<{
  targets: number;
  commands: number;
  secondGo: readonly string[];
  /** U68: where the server's value will differ from what was entered, per command. */
  resolved: readonly ResolvedCommand[];
  blocked: string | null;
  submit: SubmitState;
}>();
defineEmits<{ send: []; check: [] }>();
const title = defineModel<string>("title", { required: true });
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
</script>

<template>
  <ApPanel index="C5" title="Sequence summary" pane flush>
    <div class="flex flex-col gap-4 p-4">
      <ApStatStrip :columns="3" label="Sequence size">
        <ApStatTile label="Targets" :value="targets" />
        <ApStatTile label="Cmds" :value="commands" />
        <ApStatTile label="Uplinks" :value="uplinks" />
      </ApStatStrip>
      <ReleaseFields v-model="release" />
      <div v-if="secondGo.length" class="flex flex-col gap-2">
        <ApCallout tone="caution">Needs a second GO: {{ secondGo.join("; ") }}.</ApCallout>
        <ApSelect v-model="approver" label="Second GO from" size="compact" :options="approvers" />
      </div>
      <ApField
        v-model="title"
        label="Title"
        required
        placeholder="e.g. Load shed after VBAT red on 312"
        hint="The headline your approver and the log see."
      />
      <ApTextarea
        v-model="log"
        label="Log entry"
        :rows="3"
        :required="secondGo.length > 0"
        placeholder="Why this sequence, for the request log"
      />
      <!-- ux U68: nobody arms without seeing what the server will send instead. -->
      <div v-for="c in resolved" :key="c.position" class="flex flex-col gap-0.5">
        <p class="m-0 font-mono text-sm font-semibold text-readout">{{ c.label }}</p>
        <p v-for="line in c.lines" :key="line" class="m-0 font-mono text-sm text-text-3">
          {{ line }}
        </p>
      </div>
      <p v-if="release.expiresAt !== null" class="m-0 text-md text-text-2">
        {{ expiresWords(new Date(release.expiresAt).toISOString()) }} if not released.
      </p>
      <ApButton
        variant="primary"
        size="commit"
        class="w-full"
        :disabled="blocked !== null || submit.status === 'sending' || submit.status === 'checking'"
        :disabled-reason="
          blocked ??
          (submit.status === 'sending'
            ? 'Sending…'
            : submit.status === 'checking'
              ? 'Checking…'
              : '')
        "
        @click="$emit('send')"
      >
        {{
          submit.status === "sending"
            ? "Sending…"
            : secondGo.length
              ? `Request GO · ${plural(uplinks, "uplink")}`
              : `Arm ${plural(uplinks, "uplink")}`
        }}
      </ApButton>
      <SubmitOutcome :state="submit" @check="$emit('check')" />
      <p v-if="blocked" class="m-0 text-md text-text-3">{{ blocked }}</p>
      <p class="m-0 font-mono text-xs text-text-4 uppercase">Nothing radiates without a GO</p>
      <!-- Command.md C3 caption, now that abort exists (M20): it stops what hasn't started. -->
      <p class="m-0 font-mono text-xs text-text-4 uppercase">
        Abort available until each uplink starts
      </p>
    </div>
  </ApPanel>
</template>
