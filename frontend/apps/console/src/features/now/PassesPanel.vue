<script setup lang="ts">
import { computed } from "vue";
import { useRouter } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import { useNow, ApButton, ApEmptyState, ApGantt, ApPanel, ApRemote } from "@/ui";
import { passGantt, usePasses } from "@/features/contacts/index.ts";
import UnshownCallout from "./UnshownCallout.vue";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";

/**
 * A4 · Passes in the next 2 h (now − 15 min → now + 2 h), stations × time from the booked
 * reservations (M7), refetched on `contacts` (usePasses).
 */
const props = defineProps<{ spacecraft: readonly FleetSpacecraft[] }>();
const scope = useMissionScope();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
const query = usePasses(missionId, 15 * 60_000, 2 * 3_600_000);
const router = useRouter();
/** A bar opens that pass in the Contacts drawer (backlog §2 Now). */
function open(id: string) {
  router
    .push({ name: "ops.contacts", query: { contact: id } })
    .catch((e: unknown) => console.error("Navigation failed", e));
}

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
/** U86: passes this console couldn't read, for the line at the top of the list. */
const unshown = computed(() =>
  query.state.value.status === "ready" ? query.state.value.value.unshown : [],
);
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
      <UnshownCallout :unshown="unshown" noun="pass" />
      <ApEmptyState
        v-if="view && view.bars.length === 0 && unshown.length === 0"
        headline="No passes in the next 2 h"
      >
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
          @select="open"
        />
      </div>
    </ApRemote>
  </ApPanel>
</template>
