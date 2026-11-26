<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { describeApiError } from "@/api";
import {
  formatCount,
  plural,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApField,
  ApPageHeader,
  ApPanel,
  ApRemote,
} from "@/ui";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import SpacecraftTable from "./SpacecraftTable.vue";
import type { DirectorySummary } from "./api.ts";
import { useSpacecraftDirectory } from "./useSpacecraftDirectory.ts";

/** Setup › Spacecraft: the mission's spacecraft directory (rail 02), a page at a time (#796). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const query = ref("");
const directory = useSpacecraftDirectory(missionId, query);
const { state, refetch } = directory;

// Setup writes need manage_mission, which the server grants to organization admins (qa #4).
const session = useSession();
const canManage = computed(() => canAdministerOrganization(session, scope.value.organization));

/** The subtitle reads the server's whole-mission counts, whatever the filter or pages loaded. */
const subtitle = (s: DirectorySummary) =>
  [
    plural(s.total, "spacecraft", "spacecraft"),
    plural(s.profiles, "profile"),
    s.withoutProfile > 0 ? `${formatCount(s.withoutProfile)} without a profile` : null,
    s.withoutScid > 0 ? `${formatCount(s.withoutScid)} without a SCID` : null,
    s.withoutRoute > 0 ? `${formatCount(s.withoutRoute)} without a routing rule` : null,
    s.neverHeard > 0 ? `${formatCount(s.neverHeard)} awaiting first AOS` : null,
  ]
    .filter((part): part is string => part !== null)
    .join(" · ");
const summary = computed(() =>
  state.value.status === "ready" ? subtitle(state.value.value.meta.summary) : null,
);
const filtering = computed(() => directory.settledQuery.value !== "");

// The filter box outlives every reload its own typing causes: a settled keystroke starts the
// query over (state goes loading), so whether the mission has any craft is remembered, not read
// from the state, or the box would unmount under the cursor.
const missionHasCraft = ref(false);
watch(
  [state, missionId],
  ([s], [, before]) => {
    if (missionId.value !== before) missionHasCraft.value = false;
    if (s.status === "ready") missionHasCraft.value = s.value.meta.summary.total > 0;
  },
  { immediate: true },
);
const panel = ref<HTMLElement | null>(null);

/** After Load more, focus the first new row's link (ux U72's Load more rule). */
async function loadMore() {
  const before = state.value;
  const seen = new Set(before.status === "ready" ? before.value.items.map((r) => r.id) : []);
  await directory.more();
  await nextTick();
  const after = state.value;
  const fresh = after.status === "ready" ? after.value.items.find((r) => !seen.has(r.id)) : null;
  if (fresh)
    panel.value
      ?.querySelector<HTMLElement>(`a[href$="/spacecraft/${CSS.escape(fresh.id)}"]`)
      ?.focus();
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader :label="`${scope.mission.name} · setup`" title="Spacecraft" size="reading">
      <template v-if="summary" #subtitle>
        <span class="text-md text-text-3">{{ summary }}</span>
      </template>
      <ApButton v-if="canManage" :to="{ name: 'setup.spacecraft.new' }">Add spacecraft</ApButton>
    </ApPageHeader>

    <ApPanel index="A1" title="Directory" flush>
      <template v-if="missionHasCraft || filtering" #header>
        <div class="w-[260px]">
          <ApField
            v-model="query"
            label="Filter spacecraft"
            hidden-label
            type="search"
            placeholder="Name, SCID or profile"
          />
        </div>
      </template>
      <template v-if="state.status === 'ready'" #meta
        >{{ formatCount(state.value.items.length)
        }}{{
          filtering
            ? state.value.next !== null
              ? " shown, more match"
              : " match"
            : ` of ${formatCount(state.value.meta.summary.total)}`
        }}</template
      >
      <div ref="panel">
        <ApRemote :state="state" loading-label="Loading spacecraft…" @retry="refetch">
          <template #default="{ value }">
            <!-- A live refresh that failed keeps the rows; say so. Always mounted, its text clears (#837). -->
            <p role="status" class="px-4 text-sm text-caution-text empty:hidden">
              {{
                directory.refreshError.value
                  ? `Couldn't refresh the directory: ${describeApiError(directory.refreshError.value)}. The spacecraft shown may be out of date.`
                  : ""
              }}
            </p>
            <ApEmptyState
              v-if="value.items.length === 0 && !filtering"
              state="off"
              headline="No spacecraft yet"
              :sentence="
                canManage
                  ? 'Add one spacecraft or a whole launch batch from a profile or a manifest.'
                  : 'An organization admin adds spacecraft to this mission.'
              "
            >
              <ApButton v-if="canManage" variant="primary" :to="{ name: 'setup.spacecraft.new' }"
                >Add spacecraft</ApButton
              >
            </ApEmptyState>
            <ApEmptyState
              v-else-if="value.items.length === 0"
              headline="No spacecraft match"
              :sentence="`Nothing matches “${directory.settledQuery.value}”. Filter by name, SCID or profile.`"
            />
            <template v-else>
              <ApCallout v-if="value.meta.telemetry === 'degraded'" tone="caution"
                >Last heard may be incomplete: the telemetry history isn't answering, so only what
                arrived since the last restart shows.</ApCallout
              >
              <SpacecraftTable
                :rows="value.items"
                :degraded="value.meta.telemetry === 'degraded'"
              />
              <div
                v-if="value.next !== null"
                class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2"
              >
                <ApButton
                  size="compact"
                  variant="secondary"
                  :disabled="directory.moreBusy.value"
                  disabled-reason="Loading more spacecraft…"
                  @click="loadMore"
                  >Load more</ApButton
                >
                <!-- ux U72, a11y B6: said next to the button as an alert, always mounted. -->
                <span role="alert" class="text-sm text-caution-text">{{
                  directory.moreError.value
                    ? `Couldn't load more spacecraft: ${describeApiError(directory.moreError.value)}`
                    : ""
                }}</span>
              </div>
            </template>
          </template>
        </ApRemote>
      </div>
    </ApPanel>
  </div>
</template>
