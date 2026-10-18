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
    ><h2 class="text-base font-semibold">Spacecraft bindings</h2>
    <p class="text-sm text-base-content/60">
      Active and saved bindings using this catalog revision.
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
        <tr v-for="craft in snapshot.usage" :key="craft.id">
          <th scope="row">{{ craft.name }}</th>
          <td>
            {{ craft.active ? "Active" : "" }}{{ craft.active && craft.saved ? " · " : ""
            }}{{ craft.saved ? "Saved draft" : "" }}
          </td>
          <td>
            <CadenceLink :href="craft.href">Review changes for {{ craft.name }}</CadenceLink>
          </td>
        </tr>
      </tbody></CadenceTableFrame
    >
    <p v-else class="text-sm text-base-content/60">
      No spacecraft has saved or activated this revision yet.
      <CadenceLink :href="`/missions/${snapshot.mission_id}/spacecraft`"
        >Choose a spacecraft</CadenceLink
      >
    </p></CadenceCard
  >
</template>
