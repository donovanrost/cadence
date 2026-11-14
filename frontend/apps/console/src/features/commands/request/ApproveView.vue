<script setup lang="ts">
import { computed } from "vue";
import type { RemoteState } from "@/api/index.ts";
import { ApCheckRows, ApPanel, ApRemote, ApTag } from "@/ui";
import type { GroupRow, Preflight } from "../groups/api.ts";
import { checkMeta, checkRows } from "../groups/checks.ts";
import type { Group } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";
import { verifiersDiffer } from "../groups/verifierGroups.ts";
import VerifierGroups from "../groups/VerifierGroups.vue";
import DecisionPanel from "./DecisionPanel.vue";
import QueuePanel from "./QueuePanel.vue";
import RequestBrief from "./RequestBrief.vue";

/**
 * C2 · Approve: Q waiting on you · the request with A2 re-checked now · D your call. Under 768
 * (Mobile.md, GO polls → mobile Approve) it's one column: header, What changes (A1), Re-checked
 * (A2), then the decision; the queue is the GO polls tab there, so Q hides.
 */
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
/** U51: the reviewer sees each command whose verifiers differ across targets (no gate). */
const shortName = (id: string) =>
  props.group.targets.find((x) => x.spacecraft_id === id)?.name ?? "Unknown spacecraft";
const differing = (p: Preflight) =>
  (p.commands ?? [])
    .filter((c) => verifiersDiffer(c.verifier_groups))
    .map((c) => ({
      ...c,
      name: props.group.commands.find((x) => x.position === c.position)?.name ?? c.command_id,
    }));
</script>

<template>
  <div
    class="grid min-h-0 flex-1 grid-cols-1 gap-3 max-console:overflow-auto console:grid-cols-[280px_minmax(0,1fr)_340px]"
  >
    <QueuePanel
      class="max-md:hidden"
      :rows="queue"
      :current-id="group.id"
      :viewer-id="viewerId"
      :name-of="nameOf"
    />
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
                <div
                  v-for="c in differing(value)"
                  :key="c.position"
                  class="flex flex-col gap-1 border-t border-hairline px-4 py-3"
                >
                  <p class="m-0 flex items-center gap-2 font-mono text-sm text-readout">
                    {{ c.name }} <ApTag state="caution" label="Verifiers differ" />
                  </p>
                  <VerifierGroups :groups="c.verifier_groups" :name-of="shortName" />
                </div>
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
