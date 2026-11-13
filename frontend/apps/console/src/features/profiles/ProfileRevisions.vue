<script setup lang="ts">
import { computed } from "vue";
import { actorName, useRemoteQuery } from "@/api";
import { FieldRows, fetchEntityRevisions, type RevisionDetail } from "@/features/changes/index.ts";
import { useMissionScope } from "@/shell";
import { ApEmptyState, ApPanel, ApRemote, formatAbsolute, plural } from "@/ui";

/**
 * Profile.md History: the revisions touching this profile (api c3b07440d), newest first, each
 * with when, who, why and this profile's field diffs. `Compare` opens the revision range.
 */
const props = defineProps<{ profileId: string }>();
const scope = useMissionScope();
const revisions = useRemoteQuery(
  () => ({
    missionId: scope.value.mission.id,
    kind: "spacecraft_profile",
    entityId: props.profileId,
    limit: 50,
  }),
  fetchEntityRevisions,
);
const meta = computed(() =>
  revisions.state.value.status === "ready"
    ? plural(revisions.state.value.value.length, "revision")
    : "",
);
const fields = (r: RevisionDetail) => r.entries.flatMap((e) => e.fields);
/** The list is newest first, so the one before r is the next row. */
const previous = (list: readonly RevisionDetail[], i: number) => list[i + 1]?.revision ?? null;
</script>

<template>
  <ApPanel index="P6" title="Revisions" :meta="meta" flush>
    <ApRemote
      :state="revisions.state.value"
      loading-label="Loading revisions…"
      @retry="revisions.refetch"
    >
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.length === 0"
          state="off"
          headline="No revisions yet"
          sentence="Changes to this profile appear here once they're applied."
        />
        <ul v-else class="m-0 list-none p-0">
          <li
            v-for="(r, i) in value"
            :key="r.revision"
            class="border-t border-hairline px-4 py-3 first:border-t-0"
          >
            <p class="m-0 flex flex-wrap items-baseline gap-x-2 text-sm">
              <RouterLink
                :to="{ name: 'setup.revision', params: { revision: String(r.revision) } }"
                class="font-mono text-primary no-underline hover:underline"
                >r{{ r.revision }}</RouterLink
              >
              <span class="font-mono text-text-3">{{
                formatAbsolute(new Date(r.applied_at))
              }}</span>
              <span class="text-readout">{{ actorName(r.applied_by) }}</span>
              <span v-if="r.reason" class="text-text-2">· {{ r.reason }}</span>
              <RouterLink
                v-if="previous(value, i)"
                :to="{
                  name: 'setup.revisions.compare',
                  params: { from: String(previous(value, i)), to: String(r.revision) },
                }"
                class="ml-auto text-text-3 no-underline hover:text-readout"
                >Compare with r{{ previous(value, i) }} →</RouterLink
              >
            </p>
            <FieldRows v-if="fields(r).length > 0" :fields="fields(r)" />
          </li>
        </ul>
      </template>
    </ApRemote>
  </ApPanel>
</template>
