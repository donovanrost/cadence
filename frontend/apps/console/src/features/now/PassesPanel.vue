<script setup lang="ts">
import { computed, onScopeDispose } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { useNow, ApButton, ApEmptyState, ApGantt, ApPanel, ApRemote } from "@/ui";
import { fetchPasses, passGantt } from "@/features/contacts/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";

/**
 * A4 · Passes in the next 2 h (now − 15 min → now + 2 h), stations × time from the booked
 * reservations (M7). Polled every 30 s (contract); `contacts` invalidation joins when @/live knows it.
 */
const props = defineProps<{ spacecraft: readonly FleetSpacecraft[] }>();
const scope = useMissionScope();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
const query = useRemoteQuery(missionId, (id, signal) => {
  const t = Date.now();
  return fetchPasses(
    id,
    { from: new Date(t - 15 * 60_000), to: new Date(t + 2 * 3_600_000) },
    signal,
  );
});
const poll = setInterval(query.refetch, 30_000);
onScopeDispose(() => clearInterval(poll));

const byId = computed(() => new Map(props.spacecraft.map((sc) => [sc.id, sc])));
const view = computed(() => {
  const s = query.state.value;
  if (s.status !== "ready") return null;
  const window = { from: Date.parse(s.value.from), to: Date.parse(s.value.to) };
  return {
    window,
    ...passGantt(s.value.passes, (id) => byId.value.get(id) ?? null, now.value.getTime()),
    synthetic: s.value.passes.some((p) => p.source.synthetic),
  };
});
</script>

<template>
  <ApPanel
    index="A4"
    title="Passes · next 2 h"
    :meta="view?.synthetic ? 'synthetic windows' : undefined"
    pane
    flush
  >
    <template #meta>
      <RouterLink
        :to="{ name: 'ops.contacts' }"
        class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
        >Open contacts →</RouterLink
      >
    </template>
    <ApRemote :state="query.state.value" loading-label="LOADING PASSES…" @retry="query.refetch">
      <ApEmptyState v-if="view && view.bars.length === 0" headline="No passes in the next 2 h">
        <ApButton size="compact" :to="{ name: 'ops.contacts' }">Open contacts</ApButton>
      </ApEmptyState>
      <div v-else-if="view" class="p-3">
        <ApGantt
          label="Passes in the next two hours by station"
          :rows="view.rows"
          :bars="view.bars"
          :window="view.window"
          :now="now.getTime()"
          :lane-height="24"
        />
      </div>
    </ApRemote>
  </ApPanel>
</template>
