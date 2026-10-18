<script setup lang="ts">
import CollectionFrame from "../../shared/CollectionFrame.vue";
import CadenceHoverTableRow from "@cadence/ui/CadenceHoverTableRow.vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import type { Collection, ReadContext } from "../../shared/read-contracts";
import type { TransportRow } from "./read-contracts";
const props = defineProps<{ page: Collection<TransportRow>; context: ReadContext }>();
useManagementHeader("/missions/:mission_id/comms/transports", () => ({
  description: "Durable byte-moving capabilities for spacecraft traffic.",
  facts: [`${props.page.data.total_count} configured`],
  primary: {
    id: "new",
    label: "New transport",
    icon: "hero-plus",
    href: href("/missions/:mission_id/comms/transports/new", {
      mission_id: props.context.missionId,
    }),
  },
}));
</script>
<template>
  <CollectionFrame id="comms-transports-directory" :page="page">
    <template #columns
      ><th class="hud-label">Name</th>
      <th class="hud-label">Origin</th>
      <th class="hud-label">Capability</th>
      <th class="hud-label">Direction</th>
      <th class="hud-label">Version</th></template
    >
    <template #rows>
      <CadenceHoverTableRow
        v-for="item in page.data.items"
        :id="'transports-' + item.id"
        :key="item.id"
      >
        <td>
          <a
            :href="item.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
            >{{ item.display_name }}</a
          >
        </td>
        <td>{{ item.origin }}</td>
        <td>{{ item.transport_kind }}</td>
        <td>{{ item.direction_capability }}</td>
        <td>{{ item.version }}</td>
      </CadenceHoverTableRow>
    </template>
  </CollectionFrame>
</template>
