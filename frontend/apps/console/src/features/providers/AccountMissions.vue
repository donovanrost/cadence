<script setup lang="ts">
import type { SessionOrganization } from "@/api";

/** Provider account detail · the missions using it (links into each mission's Providers tab). */
const props = defineProps<{
  organization: SessionOrganization;
  missions: readonly Readonly<{ id: string; name: string }>[];
}>();
const slugOf = (id: string) => props.organization.missions.find((m) => m.id === id)?.slug;
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="ap-label">Missions using it</span>
    <p v-if="missions.length === 0" class="m-0 text-sm text-text-3">
      No mission uses this account yet.
    </p>
    <ul v-else class="m-0 flex list-none flex-col gap-1 p-0">
      <li v-for="m in missions" :key="m.id">
        <RouterLink
          v-if="slugOf(m.id)"
          :to="{
            name: 'setup.stations.providers',
            params: { org: organization.slug, mission: slugOf(m.id) },
          }"
          class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
          >{{ m.name }}</RouterLink
        >
        <span v-else>{{ m.name }}</span>
      </li>
    </ul>
  </div>
</template>
