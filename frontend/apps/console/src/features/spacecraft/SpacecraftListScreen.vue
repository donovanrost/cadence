<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import {
  formatCount,
  plural,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApField,
  ApPageHeader,
  ApPanel,
  ApRemote,
} from "@/ui";
import { useMissionInvalidation } from "@/live";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import SpacecraftTable from "./SpacecraftTable.vue";
import {
  fetchSpacecraftDirectory,
  matchesFilter,
  summarize,
  type SpacecraftDirectory,
} from "./api.ts";

/** Setup › Spacecraft: the mission's spacecraft directory (rail 02). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchSpacecraftDirectory);
useMissionInvalidation(missionId, ["spacecraft"], refetch);

// Setup writes need manage_mission, which the server grants to organization admins (qa #4).
const session = useSession();
const canManage = computed(() => canAdministerOrganization(session, scope.value.organization));

const query = ref("");
const filtered = (directory: SpacecraftDirectory) =>
  directory.spacecraft.filter((row) => matchesFilter(row, query.value));

const summary = computed(() => {
  if (state.value.status !== "ready") return null;
  const s = summarize(state.value.value);
  return [
    plural(s.total, "spacecraft", "spacecraft"),
    plural(s.profiles, "profile"),
    s.withoutProfile > 0 ? `${formatCount(s.withoutProfile)} without a profile` : null,
    s.withoutScid > 0 ? `${formatCount(s.withoutScid)} without a SCID` : null,
    s.withoutRoute > 0 ? `${formatCount(s.withoutRoute)} without a routing rule` : null,
    s.neverHeard > 0 ? `${formatCount(s.neverHeard)} awaiting first AOS` : null,
  ]
    .filter((part): part is string => part !== null)
    .join(" · ");
});
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader :label="`${scope.mission.name} · setup`" title="Spacecraft" size="reading">
      <template v-if="summary" #subtitle>
        <span class="text-md text-text-3">{{ summary }}</span>
      </template>
      <ApButton v-if="canManage" :to="{ name: 'setup.spacecraft.new' }">Add spacecraft</ApButton>
    </ApPageHeader>

    <ApPanel index="A1" title="Directory" flush>
      <template v-if="state.status === 'ready' && state.value.spacecraft.length > 0" #header>
        <div class="w-[260px]">
          <ApField
            v-model="query"
            label="Filter spacecraft"
            hidden-label
            type="search"
            placeholder="Name, SCID or profile"
          />
        </div>
      </template>
      <template v-if="state.status === 'ready'" #meta
        >{{ formatCount(filtered(state.value).length) }} of
        {{ formatCount(state.value.spacecraft.length) }}</template
      >
      <ApRemote :state="state" loading-label="Loading spacecraft…" @retry="refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.spacecraft.length === 0"
            state="off"
            headline="No spacecraft yet"
            :sentence="
              canManage
                ? 'Add one spacecraft or a whole launch batch from a profile or a manifest.'
                : 'An organization admin adds spacecraft to this mission.'
            "
          >
            <ApButton v-if="canManage" variant="primary" :to="{ name: 'setup.spacecraft.new' }"
              >Add spacecraft</ApButton
            >
          </ApEmptyState>
          <ApEmptyState
            v-else-if="filtered(value).length === 0"
            headline="No spacecraft match"
            :sentence="`Nothing matches “${query.trim()}”. Filter by name, SCID or profile.`"
          />
          <template v-else>
            <ApCallout v-if="value.telemetry === 'degraded'" tone="caution"
              >Last received may be incomplete: the telemetry history isn't answering, so only what
              arrived since the last restart shows.</ApCallout
            >
            <SpacecraftTable :rows="filtered(value)" :degraded="value.telemetry === 'degraded'" />
          </template>
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
