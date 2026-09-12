<script setup lang="ts">
import CollectionFrame from "../../shared/CollectionFrame.vue";
import CadenceHoverTableRow from "@cadence/ui/CadenceHoverTableRow.vue";
import type { Collection } from "../../shared/read-contracts";
import type { TransportRow } from "./read-contracts";
defineProps<{ page: Collection<TransportRow> }>();
</script>
<template>
  <CollectionFrame
    id="comms-transports-directory"
    :page="page"
    description="Durable byte-moving capabilities for spacecraft traffic."
    create-label="New transport"
  >
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
