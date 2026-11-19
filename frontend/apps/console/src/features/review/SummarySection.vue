<script setup lang="ts">
import type { RemoteState } from "@/api";
import { ApCallout, ApRemote } from "@/ui";
import CausesPanel from "./CausesPanel.vue";
import ReviewStrip from "./ReviewStrip.vue";
import StationsPanel from "./StationsPanel.vue";
import type { ReviewSummary } from "./api.ts";
import { provisionalText } from "./format.ts";

/** K3 summary: provisional note, the stat strip, R1 by station and R2 causes. */
defineProps<{ state: RemoteState<ReviewSummary> }>();
defineEmits<{ retry: [] }>();
</script>

<template>
  <ApRemote :state="state" loading-label="Loading pass results…" @retry="$emit('retry')">
    <template #default="{ value }">
      <ApCallout v-if="provisionalText(value)" tone="caution">{{
        provisionalText(value)
      }}</ApCallout>
      <ReviewStrip :summary="value" />
      <div class="grid grid-cols-1 gap-4 console:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <StationsPanel :lines="value.by_station" />
        <CausesPanel :causes="value.by_cause" />
      </div>
    </template>
  </ApRemote>
</template>
