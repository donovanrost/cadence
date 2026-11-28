<script setup lang="ts">
import { computed } from "vue";
import { describeApiError, usePagedQuery, type MissionId } from "@/api";
import { useMissionInvalidation } from "@/live";
import {
  ApButton,
  ApEmptyState,
  ApRemote,
  ApTable,
  formatCount,
  formatShort,
  type ApColumn,
} from "@/ui";
import {
  fetchMembersPage,
  membersHeading,
  retryLabel,
  type EphemerisMember,
  type MembersKey,
} from "./ephemerisMembers.ts";
import { ephemerisReasonWords, type EphemerisCause } from "./ephemerisReasons.ts";

/**
 * #972: the spacecraft of one provider_ephemeris group (Now's row opens it), paged by spacecraft
 * id. Each row is its own: the server's fixed sentence for its code, attempts, since and retry.
 */
const props = defineProps<{
  missionId: MissionId;
  providerId: string;
  cause: EphemerisCause;
  reason: string | null;
}>();
const key = computed<MembersKey>(() => ({
  missionId: props.missionId,
  providerId: props.providerId,
  cause: props.cause,
  reason: props.reason,
}));
const members = usePagedQuery(key, fetchMembersPage, (m) => m.spacecraft.id);
// setup.md: refetch on providers; stations too, as the providers read does.
useMissionInvalidation(
  computed(() => props.missionId),
  ["providers", "stations"],
  members.refetch,
);
const coded = computed(() => props.cause !== "norad_id_missing");
const columns = computed<readonly ApColumn[]>(() => [
  { key: "name", label: "Spacecraft" },
  ...(coded.value ? [{ key: "detail", label: "Why" }] : []),
  ...(props.cause === "failed"
    ? [{ key: "attempts", label: "Attempts", align: "end" as const, mono: true }]
    : []),
  { key: "since", label: "Since", mono: true },
  ...(coded.value ? [{ key: "retry", label: retryLabel(props.cause), mono: true }] : []),
]);
const at = (iso: string | null) => (iso ? formatShort(new Date(iso)) : "Not scheduled");
const named = (m: EphemerisMember) => m.spacecraft.name?.trim() || "Unknown spacecraft";
</script>

<template>
  <section :aria-label="membersHeading(cause)" class="flex flex-col border-t border-hairline">
    <h3 class="ap-label m-0 px-4 pt-3 pb-1">{{ membersHeading(cause) }}</h3>
    <p v-if="reason !== null || !coded" class="m-0 px-4 pb-2 text-sm text-text-2">
      {{ ephemerisReasonWords(cause, reason) }}
    </p>
    <ApRemote
      :state="members.state.value"
      loading-label="Loading the spacecraft…"
      @retry="members.refetch"
    >
      <template #default="{ value: page }">
        <p
          v-if="members.refreshError.value"
          role="status"
          class="m-0 px-4 pb-2 text-sm text-caution-text"
        >
          Couldn't refresh the list: {{ describeApiError(members.refreshError.value) }}. Showing
          what was read before.
        </p>
        <ApEmptyState
          v-if="page.items.length === 0"
          state="off"
          headline="No spacecraft in this group now"
          sentence="Each one has moved on since it was raised, so there's nothing left to fix here."
        />
        <ApTable
          v-else
          :columns="columns"
          :rows="page.items"
          :row-key="(m) => m.spacecraft.id"
          :caption="membersHeading(cause)"
        >
          <template #cell-name="{ row }">
            <RouterLink
              v-if="row.spacecraft.scid !== null"
              :to="{ name: 'ops.spacecraft', params: { scId: row.spacecraft.scid } }"
              class="font-semibold text-primary no-underline hover:underline max-md:hit-44"
              >{{ named(row) }}</RouterLink
            >
            <span v-else class="font-semibold">{{ named(row) }}</span>
            <span class="font-mono text-xs text-text-3">
              SCID {{ row.spacecraft.scid ?? "unknown" }}</span
            >
          </template>
          <template #cell-detail="{ row }">{{
            row.detail ?? ephemerisReasonWords(cause, row.reason)
          }}</template>
          <template #cell-attempts="{ row }">{{
            row.attempts > 0 ? formatCount(row.attempts) : ""
          }}</template>
          <template #cell-since="{ row }">{{ at(row.since) }}</template>
          <template #cell-retry="{ row }">{{ at(row.next_retry_at) }}</template>
          <template #footer>
            <div
              class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
            >
              <span>{{ formatCount(page.items.length) }} shown</span>
              <ApButton
                size="compact"
                :disabled="members.moreBusy.value || page.next === null"
                :disabled-reason="members.moreBusy.value ? 'Loading…' : 'No more spacecraft'"
                @click="members.more"
                >Load more</ApButton
              >
              <!-- It answers the person's own click: an alert, always mounted (a11y B6). -->
              <span role="alert" class="text-caution-text">{{
                members.moreError.value
                  ? `Couldn't load more: ${describeApiError(members.moreError.value)}`
                  : ""
              }}</span>
            </div>
          </template>
        </ApTable>
      </template>
    </ApRemote>
  </section>
</template>
