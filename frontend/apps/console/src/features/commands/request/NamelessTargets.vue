<script setup lang="ts">
import { computed, toRef } from "vue";
import { describeApiError, type MissionId } from "@/api/index.ts";
import { ApButton, ApRemote, formatCount } from "@/ui";
import type { Group } from "../groups/show.ts";
import { useGroupTargets } from "./useGroupPages.ts";

/**
 * #1064: the ids of a group's targets with no name, for the GO caution's Technical details (U25:
 * ids live there, never in place of a name). Read from the targets filtered to `unnamed=true`, so a
 * target past the first page is listed too; mounted only when Technical details opens.
 */
const props = defineProps<{ group: Group; missionId: MissionId }>();
const pages = useGroupTargets(
  toRef(props, "missionId"),
  toRef(props, "group"),
  computed(() => ({ unnamed: true })),
);
</script>

<template>
  <ApRemote
    :state="pages.state.value"
    loading-label="Loading the targets with no name…"
    @retry="pages.refetch"
  >
    <template #default="{ value: page }">
      <p v-if="pages.refreshError.value" role="status" class="m-0 text-caution-text">
        Couldn't refresh these: {{ describeApiError(pages.refreshError.value) }}. Showing what was
        read before.
      </p>
      <ul class="m-0 list-none p-0 font-mono">
        <li v-for="t in page.items" :key="t.spacecraft_id">{{ t.spacecraft_id }}</li>
      </ul>
      <div v-if="page.next !== null || pages.moreError.value" class="flex items-center gap-2 pt-1">
        <span
          >{{ formatCount(page.items.length) }} of {{ formatCount(page.meta.total) }} shown</span
        >
        <ApButton
          size="compact"
          :disabled="pages.moreBusy.value || page.next === null"
          :disabled-reason="pages.moreBusy.value ? 'Loading…' : 'Every target is shown'"
          @click="pages.more"
          >Load more</ApButton
        >
      </div>
      <!-- It answers the person's own click: an alert, always mounted (a11y B6). -->
      <span role="alert" class="text-caution-text">{{
        pages.moreError.value
          ? `Couldn't load more: ${describeApiError(pages.moreError.value)}`
          : ""
      }}</span>
    </template>
  </ApRemote>
</template>
