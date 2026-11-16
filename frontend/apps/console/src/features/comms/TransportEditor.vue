<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { KindEditor } from "@/features/changes/index.ts";
import { ApRemote } from "@/ui";
import { fetchTransport } from "./api.ts";

/**
 * Add or edit one transport through the change set (transport kind). `new` adds a direct transport
 * (the kind defaults origin and kind; lead 11-16, replacing the comms app's direct-write tab);
 * an id prefills from its stored document and stages schema paths (api contract).
 */
const props = defineProps<{ missionId: MissionId; transportId: string }>();
const adding = computed(() => props.transportId === "new");
const detail = useRemoteQuery(
  () => (adding.value ? null : { missionId: props.missionId, transportId: props.transportId }),
  fetchTransport,
);
</script>

<template>
  <KindEditor
    v-if="adding"
    :mission-id="missionId"
    kind="transport"
    :entity-id="null"
    :document="{}"
    name="transport"
    index="T3"
    surface="transports"
    :done="{ name: 'setup.comms.transports' }"
  />
  <ApRemote
    v-else
    :state="detail.state.value"
    loading-label="Loading transport…"
    @retry="detail.refetch"
  >
    <template #default="{ value }">
      <KindEditor
        :mission-id="missionId"
        kind="transport"
        :entity-id="value.id"
        :document="value.document"
        :name="
          typeof value.document.display_name === 'string'
            ? value.document.display_name
            : 'transport'
        "
        index="T3"
        surface="transports"
        :done="{ name: 'setup.comms.transports' }"
      />
    </template>
  </ApRemote>
</template>
