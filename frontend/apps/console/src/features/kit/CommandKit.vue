<script setup lang="ts">
import { ref } from "vue";
import {
  ApDecision,
  ApEventLine,
  ApNumberField,
  ApPanel,
  ApStationBar,
  ApStatStrip,
  ApStatTile,
  ApTakeoverHeader,
  ApVerdictSummary,
  type ApDecisionOption,
} from "@/ui";

/** Development-only review of the commanding kit with fixture values. */
const STATIONS = ["Compose", "Check", "Approve", "Release", "Radiate", "Acknowledge", "Verify"];
const setpoint = ref("8.0");
const decision = ref<"go" | "exclude" | "back" | "nogo" | null>(null);
const options: readonly ApDecisionOption<"go" | "exclude" | "back" | "nogo">[] = [
  {
    value: "go",
    title: "GO as requested",
    description: "All 98 targets (fixture)",
    commitLabel: "Sign GO · 98 targets",
  },
  {
    value: "exclude",
    title: "GO, excluding 2",
    description: "96 targets (fixture)",
    needsNote: true,
    commitLabel: "Sign GO · 96 targets",
  },
  {
    value: "back",
    title: "Send back",
    description: "Returns to Compose with your note",
    needsNote: true,
    commitLabel: "Send back",
  },
  {
    value: "nogo",
    title: "NO-GO",
    description: "Closes the request and logs why",
    needsNote: true,
    commitLabel: "Record NO-GO",
  },
];
</script>

<template>
  <ApPanel index="K3" title="Commanding kit" meta="FIXTURES" flush>
    <div class="flex flex-col gap-4 p-4">
      <ApTakeoverHeader
        title="Review REQ-0419"
        context="Approvals · fixture"
        :close="{ name: 'kit' }"
        close-label="Close review"
      >
        <template #steps>
          <ApStationBar :steps="STATIONS" :current="2" label="Stations" :collapse-future-from="4" />
        </template>
      </ApTakeoverHeader>
      <ApStationBar
        :steps="STATIONS"
        :current="[4, 5, 6]"
        label="Stations, uplink"
        :collapse-done-before="4"
        :collapse-future-from="4"
      />
      <ApVerdictSummary
        :items="[
          { key: 'id', label: 'Identity', verdict: 'go' },
          { key: 'cat', label: 'Catalog', verdict: 'go' },
          { key: 'conf', label: 'Conflicts', verdict: 'checking' },
          { key: 'two', label: 'Two-person', verdict: 'hold' },
        ]"
      />
      <ApStatStrip :columns="3" label="Pipeline (fixture)">
        <ApStatTile label="Radiating" :value="4" :share="0.04" caption="Fixture" />
        <ApStatTile label="Verified" :value="34" state="nominal" :share="0.35" caption="Fixture" />
        <ApStatTile
          label="No ACK · retry"
          :value="1"
          state="caution"
          :share="0.01"
          caption="Fixture"
        />
      </ApStatStrip>
      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <ApNumberField v-model="setpoint" label="setpoint" unit="°C" :min="0" :max="12" />
        <ol class="m-0 list-none border border-hairline p-0 py-1">
          <ApEventLine time="04:31:02Z" state="nominal" mono
            >EARENDIL-171 · <span class="text-nominal-text">VERIFIED</span> · 1.8 s</ApEventLine
          >
          <ApEventLine time="04:30:40Z" state="caution" mono
            >EARENDIL-152 · <span class="text-caution-text">NO ACK</span> · retry 1 of
            3</ApEventLine
          >
        </ol>
      </div>
      <div class="flex h-[460px] max-w-[360px] border border-hairline bg-panel">
        <ApDecision
          v-model="decision"
          :options="options"
          note-label="Note to the author"
          caption="Abort stays open to both of you"
        />
      </div>
    </div>
  </ApPanel>
</template>
