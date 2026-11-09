<script setup lang="ts">
import { computed } from "vue";
import type { RemoteState } from "@/api/index.ts";
import { ApCheckRows, ApPanel, ApRemote } from "@/ui";
import type { GroupRow, Preflight } from "../groups/api.ts";
import { checkMeta, checkRows } from "../groups/checks.ts";
import type { Group } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";
import DecisionPanel from "./DecisionPanel.vue";
import QueuePanel from "./QueuePanel.vue";
import RequestBrief from "./RequestBrief.vue";

/** C2 · Approve: Q waiting on you · the request with A2 re-checked now · D your call. */
const props = defineProps<{
  group: Group;
  review: RemoteState<Preflight>;
  queue: readonly GroupRow[];
  viewerId: string;
  canApprove: boolean;
  nameOf: PersonName;
}>();
defineEmits<{ decided: []; retryReview: [] }>();

const targetName = (id: string) => {
  const t = props.group.targets.find((x) => x.spacecraft_id === id);
  return t?.name ? `${t.name}${t.scid === null ? "" : ` (SCID ${t.scid})`}` : "Unknown spacecraft";
};
const reviewValue = computed(() => (props.review.status === "ready" ? props.review.value : null));
</script>

<template>
  <div
    class="grid min-h-0 flex-1 grid-cols-1 gap-3 max-console:overflow-auto console:grid-cols-[280px_minmax(0,1fr)_340px]"
  >
    <QueuePanel :rows="queue" :current-id="group.id" :viewer-id="viewerId" :name-of="nameOf" />
    <div class="flex min-h-0 flex-col gap-3 console:overflow-auto">
      <RequestBrief :group="group" :name-of="nameOf">
        <template #checks>
          <ApPanel
            index="A2"
            title="Re-checked at review"
            :meta="reviewValue ? checkMeta(reviewValue) : undefined"
            flush
          >
            <ApRemote :state="review" loading-label="RE-CHECKING…" @retry="$emit('retryReview')">
              <template #default="{ value }">
                <ApCheckRows :rows="checkRows(value, targetName)" />
              </template>
            </ApRemote>
          </ApPanel>
        </template>
      </RequestBrief>
    </div>
    <DecisionPanel
      :group="group"
      :review="reviewValue"
      :viewer-id="viewerId"
      :can-approve="canApprove"
      :name-of="nameOf"
      :target-name="targetName"
      @decided="$emit('decided')"
    />
  </div>
</template>
