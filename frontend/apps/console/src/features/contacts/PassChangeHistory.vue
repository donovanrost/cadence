<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery, type MissionId } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { ApCallout, ApStatusMark, ApTag } from "@/ui";
import { historyEntry } from "@/features/now/index.ts";
import { fetchPass } from "./api.ts";
import ProviderChangeBlock from "./ProviderChangeBlock.vue";

/**
 * The pass's provider changes, newest first (ux U44 pass history; api, L14 flown passes): what
 * changed, then the outcome. Open changes keep their decision block; the live one already shown
 * above from the pass's attention item is left out here.
 */
const props = defineProps<{
  missionId: MissionId;
  passId: string;
  provider: string | null;
  /** The change the attention block above already shows, if any. */
  liveChangeId: string | null;
  now: Date;
}>();
const emit = defineEmits<{ changed: [] }>();

const MAX = 50;
const missionRef = computed(() => props.missionId);
const read = useRemoteQuery(
  computed(() => ({ m: props.missionId, id: props.passId })),
  (k, signal) => fetchPass(k.m, k.id, signal),
);
useMissionInvalidation(missionRef, ["contacts", "attention"], read.refetch);

const changes = computed(() => {
  const s = read.state.value;
  const all = s.status === "ready" ? (s.value.provider_changes ?? []) : [];
  return all.filter((c) => c.id !== props.liveChangeId);
});
const shownAll = computed(() => {
  const s = read.state.value;
  return s.status === "ready" ? (s.value.provider_changes ?? []).length : 0;
});
const entries = computed(() =>
  changes.value.map((c) => ({ c, e: historyEntry(c, props.provider, props.now) })),
);
/** ux U44: the newest change expired undecided reads as a block of its own on the pass. */
const newestExpired = computed(() => {
  const first = entries.value[0];
  return first && first.e.expired ? first : null;
});
function changed() {
  read.refetch();
  emit("changed");
}
</script>

<template>
  <section v-if="entries.length" class="flex flex-col gap-2" aria-label="Provider changes">
    <h3 class="ap-label m-0">Provider changes</h3>
    <ApCallout v-if="newestExpired" tone="off">
      <p class="m-0 flex flex-wrap items-center gap-2">
        <ApTag state="off" label="Expired" />
        {{ provider ?? "The provider" }}'s change wasn't decided before the pass ended, so it
        expired.
      </p>
    </ApCallout>
    <ol class="m-0 flex list-none flex-col gap-2 p-0">
      <li v-for="{ c, e } in entries" :key="c.id" class="flex flex-col gap-1">
        <ProviderChangeBlock
          v-if="e.open"
          :mission-id="missionId"
          :target="{
            id: c.id,
            proposalHash: c.proposal_hash,
            deadlineAt: c.deadline_at,
            provider,
          }"
          :conflict="e.open"
          :fields="c.fields"
          :title="e.evidence"
          evidence=""
          :now="now"
          @changed="changed"
        />
        <template v-else>
          <p class="m-0 text-sm text-text-2">
            <ApStatusMark v-if="e.crit" state="crit" class="mr-1" />{{ e.evidence }}
          </p>
          <p v-if="e.outcome" class="m-0 text-sm text-text-3">{{ e.outcome }}</p>
        </template>
      </li>
    </ol>
    <p v-if="shownAll >= MAX" class="m-0 text-xs text-text-3">Showing the latest 50 changes.</p>
  </section>
</template>
