<script setup lang="ts">
import CollectionFrame from "../../shared/CollectionFrame.vue";
import CadenceHoverTableRow from "@cadence/ui/CadenceHoverTableRow.vue";
import type { Collection } from "../../shared/read-contracts";
import type { GroundStationRow } from "./read-contracts";
defineProps<{ page: Collection<GroundStationRow> }>();
</script>
<template>
  <CollectionFrame
    id="comms-ground-stations-directory"
    :page="page"
    description="Mission-owned antenna and site identities."
    create-label="New ground station"
  >
    <template #columns
      ><th class="hud-label">Name</th>
      <th class="hud-label">Provider</th>
      <th class="hud-label">Region</th></template
    >
    <template #rows>
      <CadenceHoverTableRow
        v-for="item in page.data.items"
        :id="'ground_stations-' + item.id"
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
        <td>{{ item.provider }}</td>
        <td>{{ item.region }}</td>
      </CadenceHoverTableRow>
    </template>
  </CollectionFrame>
</template>
