<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApCallout, formatCount, useNow } from "@/ui";
import type { PlanDetail } from "./api.ts";
import { expiredLine, noWindow } from "./lifecycle.ts";

/**
 * #273 (director's condition 2; U97/U61, #340): before deciding, the approver sees the selected
 * passes whose booking window has closed, from the plan read (the console never edits the list),
 * above Approve on Plan day and Apply on Re-plan. All closed is Approve's A6 reason instead (plan-
 * primary). When the server's next close passes while the page is open, a line says to reload.
 */
const props = defineProps<{ plan: PlanDetail; proposal?: boolean | undefined }>();
const now = useNow();
const showList = ref(false);

const expired = computed(() => {
  const e = props.plan.expired;
  return e && e.count > 0 && e.reservable_count > 0 ? e : null;
});
const sentence = computed(() => {
  const e = expired.value;
  if (!e) return null;
  const one = e.count === 1;
  const whose = props.proposal ? "the proposal's" : `R${props.plan.version}'s`;
  const closed = e.items.some(noWindow)
    ? `${one ? "its" : "their"} booking window has closed, or the provider gave none`
    : `${one ? "its" : "their"} booking window has closed`;
  const act = props.proposal ? "Applying it" : "Approving";
  const skipped = one
    ? "it's recorded as skipped"
    : `the ${formatCount(e.count)} are recorded as skipped`;
  return `${formatCount(e.count)} of ${whose} passes can't be booked any more: ${closed}. ${act} books the other ${formatCount(e.reservable_count)}; ${skipped}.`;
});
const lines = computed(() => (expired.value?.items ?? []).map((i) => expiredLine(i, now.value)));
const cappedLine = computed(() => {
  const e = expired.value;
  return e && e.count > e.items.length
    ? `Showing the first ${formatCount(e.items.length)} of ${formatCount(e.count)}.`
    : null;
});
/** The server's next close (its margin applied), never AOS: no line when it doesn't send one. */
const closedSinceLoad = computed(() => {
  const next = props.plan.next_expiry_at;
  return next ? now.value.getTime() >= Date.parse(next) : false;
});
</script>

<template>
  <ApCallout v-if="sentence" tone="caution">
    <span class="flex flex-col gap-1">
      <span class="flex flex-wrap items-center gap-x-3 gap-y-1">
        <span>{{ sentence }}</span>
        <ApButton
          v-if="lines.length > 0"
          variant="ghost"
          size="compact"
          :aria-expanded="showList"
          @click="showList = !showList"
          >{{ showList ? "Hide" : `Show ${formatCount(expired?.count ?? 0)}` }}</ApButton
        >
      </span>
      <span v-if="showList" class="flex max-h-64 flex-col gap-0.5 overflow-y-auto">
        <span v-for="(line, i) in lines" :key="i" class="font-mono text-sm text-text-2 tabular">{{
          line
        }}</span>
        <span v-if="cappedLine" class="text-sm text-text-3">{{ cappedLine }}</span>
      </span>
    </span>
  </ApCallout>
  <ApCallout v-if="closedSinceLoad" tone="caution">
    A pass's booking window has closed since this loaded. Reload to update the list.
  </ApCallout>
</template>
