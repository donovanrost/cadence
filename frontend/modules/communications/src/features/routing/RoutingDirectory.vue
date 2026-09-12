<script setup lang="ts">
import CollectionFrame from "../../shared/CollectionFrame.vue";
import CadenceHoverTableRow from "@cadence/ui/CadenceHoverTableRow.vue";
import type { Collection } from "../../shared/read-contracts";
import type { RoutingRow } from "./read-contracts";
defineProps<{ page: Collection<RoutingRow> }>();
</script>
<template>
  <CollectionFrame
    id="comms-routing-directory"
    :page="page"
    description="Saved bindings between spacecraft and mission transports."
    create-label="New routing rule"
  >
    <template #columns
      ><th class="hud-label">Name</th>
      <th class="hud-label">Spacecraft</th>
      <th class="hud-label">Transport</th>
      <th class="hud-label">Direction</th>
      <th class="hud-label">Enabled</th></template
    >
    <template #rows>
      <CadenceHoverTableRow
        v-for="item in page.data.items"
        :id="'routing-' + item.id"
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
        <td>{{ item.spacecraft_name }}</td>
        <td>{{ item.transport_name }}</td>
        <td>{{ item.direction }}</td>
        <td>{{ item.enabled ? "Yes" : "No" }}</td>
      </CadenceHoverTableRow>
    </template>
  </CollectionFrame>
</template>
