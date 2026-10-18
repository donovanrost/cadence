<script setup lang="ts">
import { computed } from "vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import { readSpacecraftUsage } from "./spacecraft-usage";
const props = defineProps<{ data: unknown }>();
const snapshot = computed(() => readSpacecraftUsage(props.data));
</script>
<template>
  <CadenceCard
    id="catalog-spacecraft-usage"
    class="card border border-base-300 bg-base-200"
    body-class="card-body p-6"
    ><h2 class="text-base font-semibold">Spacecraft usage</h2>
    <p class="text-sm text-base-content/60">
      Active means this revision is in the spacecraft’s active configuration. Saved configuration
      means it is selected in the latest saved configuration, which may also be active. Unsaved
      selections are not included.
    </p>
    <CadenceTableFrame v-if="snapshot.usage.length" class="table-sm"
      ><thead>
        <tr>
          <th scope="col">Spacecraft</th>
          <th scope="col">Usage</th>
          <th scope="col">Configuration</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="craft in snapshot.usage"
          :id="`catalog-spacecraft-usage-${craft.id}`"
          :key="craft.id"
        >
          <th scope="row">{{ craft.name }}</th>
          <td>
            {{ craft.active ? "Active" : "" }}{{ craft.active && craft.saved ? " · " : ""
            }}{{ craft.saved ? "Saved configuration" : "" }}
          </td>
          <td>
            <CadenceLink :href="craft.href">Review changes for {{ craft.name }}</CadenceLink>
          </td>
        </tr>
      </tbody></CadenceTableFrame
    >
    <p
      v-if="snapshot.total_count > snapshot.usage.length"
      id="catalog-spacecraft-usage-limit"
      class="text-sm text-base-content/60"
    >
      Showing {{ snapshot.usage.length }} of {{ snapshot.total_count }} spacecraft.
    </p>
    <p
      v-if="snapshot.total_count === 0"
      id="catalog-spacecraft-usage-empty"
      class="text-sm text-base-content/60"
    >
      Imported and available to select. No spacecraft has this revision in an active or saved
      configuration.
      <CadenceLink :href="`/missions/${snapshot.mission_id}/spacecraft`"
        >Choose a spacecraft</CadenceLink
      >
    </p></CadenceCard
  >
</template>
