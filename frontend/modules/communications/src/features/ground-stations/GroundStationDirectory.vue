<script setup lang="ts">
import CollectionFrame from "../../shared/CollectionFrame.vue";
import CadenceHoverTableRow from "@cadence/ui/CadenceHoverTableRow.vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import type { Collection, ReadContext } from "../../shared/read-contracts";
import type { GroundStationRow } from "./read-contracts";
const props = defineProps<{ page: Collection<GroundStationRow>; context: ReadContext }>();
useManagementHeader("/missions/:mission_id/comms/ground-stations", () => ({
  description: "Mission-owned antenna and site identities.",
  facts: [`${props.page.data.total_count} configured`],
  primary: {
    id: "new",
    label: "New ground station",
    icon: "hero-plus",
    href: href("/missions/:mission_id/comms/ground-stations/new", {
      mission_id: props.context.missionId,
    }),
  },
}));
</script>
<template>
  <CollectionFrame id="comms-ground-stations-directory" :page="page">
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
