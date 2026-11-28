<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConnection, useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApEmptyState, ApRemote } from "@/ui";
import ViewerBody from "../viewer/ViewerBody.vue";
import { useDashboardView } from "../viewer/useDashboardView.ts";
import { liveSnapshot } from "../model/live-merge.ts";
import { LIVE_PUSH, useDashboardLive } from "../viewer/useDashboardLive.ts";
import { fetchPlaylist, playlistDeleted } from "./api.ts";
import PresentLine from "./PresentLine.vue";
import { usePresent } from "./usePresent.ts";
import { focusedControlOwns, inDialog, refocus } from "../focus-fallback.ts";

/**
 * Present a playlist (ux): a kiosk takeover rotating its dashboards through the viewer's own read
 * (D5, live), with ←/→ to step, Space to pause and Esc to leave.
 */
const route = useRoute("ops.dashboards.present");
const router = useRouter();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const id = computed(() =>
  typeof route.params.playlistId === "string" ? route.params.playlistId : "",
);
const playlist = useRemoteQuery(
  computed(() => (id.value ? JSON.stringify([missionId.value, id.value]) : null)),
  (_k, signal) => fetchPlaylist(missionId.value, id.value, signal),
);
// An edit or a delete reaches a running kiosk: playlist writes fire `dashboards` (§D23).
useMissionInvalidation(
  computed<MissionId | null>(() => missionId.value),
  ["dashboards"],
  playlist.refetch,
);
const ready = computed(() =>
  playlist.state.value.status === "ready" ? playlist.state.value.value : null,
);
const deleted = computed(
  () => playlist.state.value.status === "failed" && playlistDeleted(playlist.state.value.error),
);
const show = usePresent(
  computed(() => ready.value?.dashboards ?? []),
  computed(() => ready.value?.dwell_seconds ?? 30),
);
const dashboardId = computed(() => show.current.value?.id ?? null);
// Each dashboard opens on its own defaults; D5 loads it, the channel (C1) keeps it live.
const runtime = ref({ from: "", to: "", spacecraftId: "" });
const view = useDashboardView(missionId, dashboardId, runtime, {
  refreshMs: ref(2_000),
  sliding: ref(true),
  paused: ref(LIVE_PUSH),
});
const live = useDashboardLive(missionId, dashboardId, runtime, ref(2_000), ref(false));
const shown = computed(() => {
  const s = view.state.value;
  const pushed =
    s.status === "ready" ? liveSnapshot(live.board.value, s.value.dashboard.current_version) : null;
  return s.status === "ready" && pushed ? { ...s, value: { ...s.value, snapshot: pushed } } : s;
});
const connection = useConnection();
/** Esc or Exit: back to Playlists, whose Present for this playlist takes focus again (ux). */
const leave = () =>
  void router.push({ name: "ops.dashboards.playlists", state: { presentFocus: id.value } });
/**
 * From anywhere in the takeover, but not from a sheet it opened (Inspect's Esc closes only it),
 * and not over a focused control that uses the key (B8: Space on a button presses it).
 */
function onKey(event: KeyboardEvent) {
  if (inDialog(event) || focusedControlOwns(event)) return;
  if (event.key === "ArrowRight") show.next();
  else if (event.key === "ArrowLeft") show.previous();
  else if (event.key === " ") {
    event.preventDefault();
    show.togglePause();
  } else if (event.key === "Escape") leave();
}
/** B4, A5: each step re-reads the board; focus that was in the old one goes to the new heading. */
const heading = ref<HTMLElement | null>(null);
watch(
  () => shown.value.status,
  () => refocus(heading.value),
  { flush: "post" },
);
onMounted(() => window.addEventListener("keydown", onKey));
onBeforeUnmount(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <PresentLine
    :name="ready?.name ?? 'Playlist'"
    :position="show.total.value ? show.index.value + 1 : 0"
    :total="show.total.value"
    :remaining-ms="show.remainingMs.value"
    :paused="show.paused.value"
    :current="show.current.value?.name ?? ''"
    :failed="shown.status === 'failed'"
    :skipped="show.skipped.value"
    @exit="leave"
  />
  <ApEmptyState
    v-if="deleted"
    headline="This playlist was deleted."
    sentence="Press Esc or Exit to go back to Playlists."
    state="off"
  />
  <ApRemote v-else :state="playlist.state.value" @retry="playlist.refetch">
    <template #default="{ value }">
      <ApEmptyState
        v-if="show.total.value === 0"
        :headline="
          value.dashboards.length
            ? 'Every dashboard in this playlist is archived.'
            : 'This playlist has no dashboards.'
        "
        sentence="Edit the playlist to add some."
        state="off"
      />
      <section
        v-else
        :aria-label="show.current.value?.name ?? 'Dashboard'"
        class="flex min-h-0 flex-1 flex-col gap-2"
      >
        <h2 ref="heading" class="m-0 font-display text-sm uppercase tracking-title text-text-2">
          {{ show.current.value?.name }}
        </h2>
        <ViewerBody :state="shown" :stale="connection === 'offline'" @retry="view.refetch" />
      </section>
    </template>
  </ApRemote>
</template>
