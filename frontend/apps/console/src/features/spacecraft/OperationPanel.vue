<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { isError, useRemoteQuery, type ApiError } from "@/api";
import {
  FailureOutcomeCallout,
  failureOutcome,
  fetchKindSchema,
  refreshConfigState,
  stageChange,
  useConfigState,
  type FailureOutcome,
} from "@/features/changes/index.ts";
import { ApButton, ApPanel, ApSegmented, ApSheet, ApTag, type ApSegment } from "@/ui";
import type { SpacecraftDetail } from "./detail.ts";
import {
  alreadyStagedLine,
  offConsequence,
  offTitle,
  operationRows,
  stagedSwitch,
  switchHelp,
  switchOp,
  switchSummary,
  type SwitchKey,
} from "./operation.ts";

/**
 * U40 Operation: Commanding and Telemetry as running now, changed here (#309). Turning one on
 * stages it; turning one off first states what it stops (a sheet, focus on Cancel). Until it's
 * applied the row shows the staged target with `STAGED · APPLIES WITH r7`.
 */
const props = defineProps<{ missionId: MissionId; detail: SpacecraftDetail; canStage: boolean }>();
// ux: the help is the schema's, so the panel and the edit form can't drift.
const schema = useRemoteQuery(
  () => ({ missionId: props.missionId, kind: "spacecraft" as const }),
  fetchKindSchema,
);
const config = useConfigState(props.missionId);
const ready = computed(() =>
  config.state.value.status === "ready" ? config.state.value.value : null,
);
const name = computed(() => props.detail.spacecraft.name);
const rows = computed(() => {
  const s = schema.state.value;
  return operationRows(props.detail).map((row) => ({
    ...row,
    help: switchHelp(s.status === "ready" ? s.value : null, row.key),
    staged: stagedSwitch(ready.value?.change_set, props.detail.spacecraft.id, row.key),
  }));
});
const appliesWith = computed(() => (ready.value ? `r${ready.value.head.revision + 1}` : null));
type Row = (typeof rows.value)[number];
type Choice = "on" | "off" | "unset";
/** The staged target, else the running value; "unset" (neither selected) while not set (U40). */
const choice = (row: Row): Choice => {
  const on = row.staged ?? row.on;
  return on === null ? "unset" : on ? "on" : "off";
};
const options: readonly ApSegment<Choice>[] = [
  { value: "on", label: "On" },
  { value: "off", label: "Off" },
];

const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const pendingOff = ref<SwitchKey | null>(null);
const busy = ref<SwitchKey | null>(null);
const failure = ref<Readonly<{ key: SwitchKey; outcome: FailureOutcome }> | null>(null);

function choose(key: SwitchKey, value: Choice) {
  failure.value = null;
  if (value === "unset") return;
  if (value === "on") return void stage(key, true);
  pendingOff.value = key;
  sheet.value?.open();
}
async function stage(key: SwitchKey, on: boolean) {
  if (busy.value) return;
  busy.value = key;
  try {
    const r = await stageChange(props.missionId, {
      summary: switchSummary(name.value, key, on),
      source: { surface: "spacecraft" },
      ops: [switchOp(props.detail.spacecraft.id, key, on)],
    });
    if (!r.ok) return void (failure.value = { key, outcome: refusal(r.error, key) });
    refreshConfigState(props.missionId);
  } finally {
    busy.value = null;
  }
}
/** U20/U79: the refusal in words; path_already_staged names the way back (mms-ux, #427). */
function refusal(error: ApiError, key: SwitchKey): FailureOutcome {
  if (!isError(error, "path_already_staged")) return failureOutcome(error, "staged");
  return {
    changed: false,
    sentence: alreadyStagedLine(name.value, key),
    link: { label: "Open change set", to: { name: "setup.changes" } },
  };
}
async function confirmOff() {
  const key = pendingOff.value;
  sheet.value?.close();
  pendingOff.value = null;
  if (key) await stage(key, false);
}
</script>

<template>
  <ApPanel index="D5" title="Operation">
    <ul class="m-0 flex list-none flex-col divide-y divide-hairline p-0">
      <li v-for="row in rows" :key="row.key" class="flex flex-col gap-2 py-3 first:pt-0 last:pb-0">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="flex min-w-0 flex-1 flex-col gap-1">
            <span class="text-base text-readout">{{ row.label }}</span>
            <span v-if="row.help" class="text-sm text-text-2">{{ row.help }}</span>
            <span class="text-md text-readout">{{ row.sentence }}</span>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <!-- U40: the revision keeps its lower-case r ("r7", never a plan's "R7"; mms-ux). -->
            <ApTag v-if="row.staged !== null && appliesWith" state="caution"
              >Staged · applies with <span class="normal-case">{{ appliesWith }}</span></ApTag
            >
            <ApTag v-else-if="row.on === null" state="off" label="Not set" />
            <ApSegmented
              v-if="canStage"
              :options="options"
              :model-value="choice(row)"
              :label="row.label"
              @update:model-value="choose(row.key, $event)"
            />
            <template v-else>
              <ApTag v-if="row.on === true" state="nominal" label="On" />
              <ApTag v-else-if="row.on === false" state="off" label="Off" />
            </template>
          </div>
        </div>
        <FailureOutcomeCallout v-if="failure?.key === row.key" :outcome="failure.outcome" />
      </li>
    </ul>
    <!-- U40: no typed confirm; the sheet states the consequence. a11y A1: it opens on Cancel. -->
    <ApSheet ref="sheet" :title="pendingOff ? offTitle(name, pendingOff) : ''" width="narrow">
      <p class="m-0 text-md text-text-2">
        {{ pendingOff ? offConsequence(name, pendingOff) : "" }}
      </p>
      <template #footer>
        <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
        <ApButton
          variant="danger"
          :disabled="busy !== null"
          disabled-reason="Staging…"
          @click="confirmOff"
          >Stage</ApButton
        >
      </template>
    </ApSheet>
  </ApPanel>
</template>
