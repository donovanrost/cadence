<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { KindEditor } from "@/features/changes/index.ts";
import { ApPanel, ApRemote, ApSegmented } from "@/ui";
import { fetchTransport } from "./api.ts";
import ProviderTransportForm from "./ProviderTransportForm.vue";

/**
 * Add or edit one transport through the change set (transport kind; comms parity 1 and 2). A new
 * transport is direct (the schema form) or provider managed (provider → service → delivery);
 * an existing one opens the form for its origin, prefilled from its stored document.
 */
const props = defineProps<{ missionId: MissionId; transportId: string }>();
const adding = computed(() => props.transportId === "new");
const detail = useRemoteQuery(
  () => (adding.value ? null : { missionId: props.missionId, transportId: props.transportId }),
  fetchTransport,
);
const origin = ref<"direct" | "provider_managed">("direct");
const origins = [
  { value: "direct" as const, label: "Direct" },
  { value: "provider_managed" as const, label: "Provider managed" },
];
const done = { name: "setup.comms.transports" } as const;
const managed = (doc: Readonly<Record<string, unknown>>) => doc["origin"] === "provider_managed";
const nameOf = (doc: Readonly<Record<string, unknown>>) =>
  typeof doc["display_name"] === "string" ? doc["display_name"] : "transport";
</script>

<template>
  <template v-if="adding">
    <ApSegmented v-model="origin" :options="origins" label="Origin" />
    <KindEditor
      v-if="origin === 'direct'"
      :mission-id="missionId"
      kind="transport"
      :entity-id="null"
      :document="{}"
      name="transport"
      index="T3"
      surface="transports"
      :done="done"
    />
    <ApPanel v-else index="T3" title="Add transport">
      <ProviderTransportForm
        :mission-id="missionId"
        :entity-id="null"
        :document="{}"
        :done="done"
      />
    </ApPanel>
  </template>
  <ApRemote
    v-else
    :state="detail.state.value"
    loading-label="Loading transport…"
    @retry="detail.refetch"
  >
    <template #default="{ value }">
      <ApPanel v-if="managed(value.document)" index="T3" :title="`Edit ${nameOf(value.document)}`">
        <ProviderTransportForm
          :mission-id="missionId"
          :entity-id="value.id"
          :document="value.document"
          :done="done"
        />
      </ApPanel>
      <KindEditor
        v-else
        :mission-id="missionId"
        kind="transport"
        :entity-id="value.id"
        :document="value.document"
        :name="nameOf(value.document)"
        index="T3"
        surface="transports"
        :done="done"
      />
    </template>
  </ApRemote>
</template>
