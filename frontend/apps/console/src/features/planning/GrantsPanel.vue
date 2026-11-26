<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useSession } from "@/shell";
import { ApButton, ApEmptyState, ApPanel, ApRemote, ApTable, type ApColumn } from "@/ui";
import GrantActions from "./GrantActions.vue";
import GrantNarrow from "./GrantNarrow.vue";
import GrantResume from "./GrantResume.vue";
import GrantRevoke from "./GrantRevoke.vue";
import GrantSheet from "./GrantSheet.vue";
import GrantState from "./GrantState.vue";
import GrantWaiting from "./GrantWaiting.vue";
import { decideOffer } from "./grant-words.ts";
import { canText, fetchGrants, identityName, limitsText, untilText, type Grant } from "./grants.ts";

/** Policy › Grants (L3, U105): what lets a service identity act without a person. */
const props = defineProps<{ missionId: MissionId }>();
const viewerId = useSession().user.id;
const grants = useRemoteQuery(() => props.missionId, fetchGrants);
const ready = computed(() =>
  grants.state.value.status === "ready" ? grants.state.value.value : null,
);
const canManage = computed(() => ready.value?.permissions.includes("grants.manage") ?? false);
const waiting = computed(
  () => ready.value?.grants.filter((g) => decideOffer(g).kind !== "none") ?? [],
);
const columns = computed<readonly ApColumn[]>(() => [
  { key: "who", label: "Service identity" },
  { key: "can", label: "Can" },
  { key: "limits", label: "Limits", mono: true },
  { key: "until", label: "Valid until", mono: true },
  { key: "state", label: "State" },
  ...(canManage.value ? [{ key: "act", label: "Action", hiddenLabel: true }] : []),
]);
const sheet = ref<InstanceType<typeof GrantSheet> | null>(null);
const revoke = ref<InstanceType<typeof GrantRevoke> | null>(null);
const narrow = ref<InstanceType<typeof GrantNarrow> | null>(null);
const resume = ref<InstanceType<typeof GrantResume> | null>(null);
/** The last act's result (a11y B6: an always-present status region, hidden while empty). */
const said = ref("");
function done(text: string) {
  said.value = text;
  grants.refetch();
}
const replaced = (g: Grant) =>
  ready.value?.grants.some((p) => p.state === "proposed" && p.replaces_grant_id === g.id) ?? false;
</script>

<template>
  <GrantWaiting
    v-for="g in waiting"
    :key="g.id"
    :mission-id="missionId"
    :grant="g"
    :viewer-id="viewerId"
    @decided="done"
  />
  <ApPanel index="G1" title="Grants" flush>
    <template v-if="canManage" #header>
      <ApButton size="compact" variant="primary" @click="sheet?.open()">Grant automation…</ApButton>
    </template>
    <p
      role="status"
      :class="said ? 'm-0 border-b border-hairline px-4 py-2.5 text-md text-readout' : 'sr-only'"
    >
      {{ said }}
    </p>
    <ApRemote :state="grants.state.value" loading-label="Loading grants…" @retry="grants.refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.grants.length === 0"
          state="off"
          headline="No grants"
          sentence="Without a grant, a person submits every plan Cadence drafts."
        />
        <ApTable
          v-else
          :columns="columns"
          :rows="value.grants"
          :row-key="(g: Grant) => g.id"
          caption="Automation grants"
        >
          <template #cell-who="{ row }">{{ identityName(row) }}</template>
          <template #cell-can="{ row }">{{ canText(row) }}</template>
          <template #cell-limits="{ row }">{{ limitsText(row) }}</template>
          <template #cell-until="{ row }">{{ untilText(row) }}</template>
          <template #cell-state="{ row }"
            ><GrantState :grant="row" :setting="value.approval_setting"
          /></template>
          <template #cell-act="{ row }"
            ><GrantActions
              :grant="row"
              @resume="resume?.open(row)"
              @narrow="narrow?.open(row)"
              @revoke="revoke?.open(row, replaced(row))"
          /></template>
        </ApTable>
        <p v-if="!canManage" class="m-0 px-4 py-3 text-sm text-text-3">
          Org admins grant automation.
        </p>
        <GrantSheet ref="sheet" :mission-id="missionId" :grants="value" @granted="done" />
      </template>
    </ApRemote>
    <GrantRevoke ref="revoke" :mission-id="missionId" @revoked="done" />
    <GrantNarrow ref="narrow" :mission-id="missionId" @narrowed="done" />
    <GrantResume ref="resume" :mission-id="missionId" @resumed="done" />
  </ApPanel>
</template>
