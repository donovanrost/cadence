<script setup lang="ts">
import { computed } from "vue";
import type { OpsPageContext, SettledOpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import { WorkspaceSnapshotCanvas } from "../../workspace";
import type { Presentation } from "./contracts";
import { usePlaylistPlayback } from "./usePlaylistPlayback";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  model: Presentation;
  context: OpsPageContext;
  port: SettledOpsPageNavigationPort;
  refresh: () => Promise<void>;
}>();
const { playing, advancing, notice, base, step, toggle, navigate } = usePlaylistPlayback(props);
const dashboardContext = computed(() => ({ ...props.context, resourceId: props.model.current.id }));
</script>
<template>
  <section
    id="playlist-presentation-feature"
    class="min-w-0 space-y-4 p-4 lg:p-6"
    :data-wallboard-mode="model.playlist.wallboard_mode"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 border border-primary/25 bg-primary/5 p-4"
    >
      <div class="min-w-0">
        <p class="hud-label">
          {{ model.playlist.wallboard_mode ? "Wallboard" : "Playlist" }} · {{ model.playlist.name }}
        </p>
        <h2 id="playlist-current-name" class="mt-2 break-words text-xl font-semibold">
          {{ model.current.name || "Unavailable dashboard" }}
        </h2>
        <p id="playlist-position" class="mt-2 font-mono text-xs">
          {{ model.index + 1 }} / {{ model.total }} · {{ model.playlist.dwell_seconds }}s per entry
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button id="playlist-previous" class="btn btn-sm" :disabled="advancing" @click="step(-1)">
          Previous</button
        ><button
          id="playlist-play-pause"
          class="btn btn-sm"
          :disabled="advancing"
          :aria-pressed="playing"
          @click="toggle()"
        >
          {{ playing ? "Pause" : "Play" }}</button
        ><button id="playlist-next" class="btn btn-sm" :disabled="advancing" @click="step(1)">
          Next</button
        ><button id="playlist-refresh" class="btn btn-ghost btn-sm" @click="refresh()">
          Refresh
        </button>
      </div>
    </header>
    <div class="flex flex-wrap justify-between gap-2 text-xs text-base-content/60">
      <p id="playlist-freshness">
        Published snapshot loaded {{ model.loaded_at }}. Updates arrive on refresh or entry change;
        this is not a live stream.
      </p>
      <a id="playlist-exit" :href="base" class="underline" @click="navigate($event, base)"
        >Exit to dashboards</a
      >
    </div>
    <p v-if="advancing" id="playlist-advancing" role="status" class="text-sm text-warning">
      Loading the next entry.
    </p>
    <p v-if="notice" id="playlist-navigation-notice" role="status" class="text-sm text-warning">
      {{ notice }}
    </p>
    <WorkspaceSnapshotCanvas
      v-if="model.current.snapshot"
      :key="model.current.id"
      :snapshot="model.current.snapshot"
      :context="dashboardContext"
      instance-id="playlist-dashboard"
    />
    <div
      v-else
      id="playlist-current-unavailable"
      role="status"
      class="border border-warning/30 bg-warning/5 p-8 text-center"
    >
      <h3 class="font-semibold">This entry cannot be presented</h3>
      <p class="mt-3 text-sm text-base-content/60">
        It may be unpublished, archived or unavailable. Its position is retained. Use Next to
        continue; no draft is substituted.
      </p>
    </div>
  </section>
</template>
