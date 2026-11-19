<script setup lang="ts">
import { ref } from "vue";
import type { RemoteState } from "@/api";
import { ApCallout, ApEmptyState, ApRemote } from "@/ui";
import type { DashboardView } from "../api.ts";
import DashboardGrid from "./DashboardGrid.vue";
import InspectSheet from "./InspectSheet.vue";

/** The read-only board: the remote state, an unsaved or empty dashboard, or the grid. */
defineProps<{ state: RemoteState<DashboardView>; stale: boolean }>();
const emit = defineEmits<{ retry: [] }>();
const inspect = ref<InstanceType<typeof InspectSheet> | null>(null);
</script>

<template>
  <ApRemote :state="state" @retry="emit('retry')">
    <template #default="{ value }">
      <ApEmptyState
        v-if="value.snapshot === null"
        headline="This dashboard has no saved version yet."
        sentence="Its author needs to save it before others can view it."
        state="off"
      />
      <ApCallout v-else-if="value.snapshot.placements.length === 0" tone="info">
        This dashboard has no widgets yet.
      </ApCallout>
      <DashboardGrid
        v-else
        :class="{ 'opacity-60': stale }"
        :snapshot="value.snapshot"
        @inspect="inspect?.open($event)"
      />
    </template>
  </ApRemote>
  <InspectSheet ref="inspect" />
</template>
