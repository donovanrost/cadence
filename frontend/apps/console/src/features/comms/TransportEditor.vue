<script setup lang="ts">
import { useRemoteQuery } from "@/api";
import { KindEditor } from "@/features/changes/index.ts";
import { ApRemote } from "@/ui";
import { fetchTransport } from "./api.ts";

/** Edit one transport: prefill from its stored document, stage schema paths (api contract). */
const props = defineProps<{ missionId: string; transportId: string }>();
const detail = useRemoteQuery(
  () => ({ missionId: props.missionId, transportId: props.transportId }),
  fetchTransport,
);
</script>

<template>
  <ApRemote :state="detail.state.value" loading-label="Loading transport…" @retry="detail.refetch">
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
