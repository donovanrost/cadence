<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import { missionHref, type OrganizationHomeModel } from "./contracts";
const props = defineProps<{ model: OrganizationHomeModel }>();
useManagementHeader("/", () => ({
  title: props.model.organization.name,
  identifier: props.model.organization.slug,
  primary: {
    id: "organization-new-mission",
    label: "New mission",
    icon: "hero-plus",
    href: href("/missions/new"),
  },
}));
const createdDate = (value: string) =>
  new Intl.DateTimeFormat("en", {
    year: "numeric",
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(new Date(value));
</script>
<template>
  <div id="organization-home-page" class="space-y-6">
    <div id="organization-stats" class="grid gap-4 md:grid-cols-3">
      <CadenceCard
        id="organization-stat-missions"
        class="card bg-base-200 border border-base-300"
        body-class="p-6"
      >
        <h2 class="hud-label">Missions</h2>
        <p class="mt-2 font-mono text-3xl font-bold">{{ model.counts.missions }}</p>
      </CadenceCard>
      <CadenceCard
        id="organization-stat-spacecraft"
        class="card bg-base-200 border border-base-300"
        body-class="p-6"
      >
        <h2 class="hud-label">Spacecraft</h2>
        <p class="mt-2 font-mono text-3xl font-bold">{{ model.counts.spacecraft }}</p>
      </CadenceCard>
      <CadenceCard
        id="organization-stat-members"
        class="card bg-base-200 border border-base-300"
        body-class="p-6"
      >
        <h2 class="hud-label">Active memberships</h2>
        <p class="mt-2 font-mono text-3xl font-bold">{{ model.counts.active_memberships }}</p>
      </CadenceCard>
    </div>
    <CadenceCard
      id="organization-recent-missions"
      class="card bg-base-200 border border-base-300"
      body-class="p-6 space-y-5"
    >
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold">Recently created missions</h2>
          <p class="mt-1 text-sm text-base-content/70">
            The three newest missions in this organization.
          </p>
        </div>
        <a id="organization-all-missions" href="/missions" class="btn btn-ghost btn-sm"
          >All missions</a
        >
      </div>
      <div
        v-if="!model.recent_missions.length"
        id="organization-missions-empty"
        class="rounded border border-dashed border-base-300 p-6 text-center"
      >
        <h3 class="font-semibold">No missions yet</h3>
        <p class="mt-2 text-sm text-base-content/70">
          Create a mission to begin configuring your spacecraft and operations.
        </p>
      </div>
      <ul v-else class="divide-y divide-base-300">
        <li
          v-for="mission in model.recent_missions"
          :id="`organization-recent-mission-${mission.id}`"
          :key="mission.id"
          class="py-4"
        >
          <a :href="missionHref(mission.id)" class="link font-semibold break-words">{{
            mission.name
          }}</a>
          <p class="mt-1 text-sm font-mono text-base-content/70 break-all">{{ mission.slug }}</p>
          <p class="mt-2 text-xs text-base-content/60">
            Created
            <time :datetime="mission.created_at">{{ createdDate(mission.created_at) }}</time> UTC
          </p>
        </li>
      </ul>
    </CadenceCard>
  </div>
</template>
