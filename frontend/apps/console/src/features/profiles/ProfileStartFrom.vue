<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { useRemoteQuery } from "@/api";
import { ApEmptyState, ApPanel, ApRemote } from "@/ui";
import { fetchProfiles, protocolLine } from "./api.ts";

/** A blank profile needs the server's field list; until it's served, start from an existing one. */
const props = defineProps<{ missionId: MissionId }>();
const profiles = useRemoteQuery(() => props.missionId, fetchProfiles);
</script>

<template>
  <ApPanel index="N1" title="Start from a profile" flush>
    <ApRemote
      :state="profiles.state.value"
      loading-label="Loading profiles…"
      @retry="profiles.refetch"
    >
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.length === 0"
          state="off"
          headline="No profile to start from"
          sentence="This console can't list a new profile's fields yet, so a new profile starts as a copy of an existing one."
        />
        <template v-else>
          <p class="m-0 px-4 pt-3 text-md text-text-3">
            A new profile starts as a copy. Change what differs before staging it.
          </p>
          <ul class="m-0 flex list-none flex-col p-0 py-2">
            <li v-for="p in value" :key="p.id" class="flex items-baseline gap-3 px-4 py-2">
              <RouterLink
                :to="{ name: 'setup.profile.new', query: { from: p.id } }"
                class="font-semibold text-readout hover:underline"
                >{{ p.name }}</RouterLink
              >
              <span class="font-mono text-xs text-text-3">{{ protocolLine(p) }}</span>
            </li>
          </ul>
        </template>
      </template>
    </ApRemote>
  </ApPanel>
</template>
