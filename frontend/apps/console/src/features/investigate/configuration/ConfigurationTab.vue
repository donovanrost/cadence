<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { useCanStage } from "@/features/changes/index.ts";
import {
  ApButton,
  ApCallout,
  ApEmptyState,
  ApKeyValue,
  ApListRow,
  ApPanel,
  ApRemote,
  ApTag,
} from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import {
  catalogCaution,
  fetchConfiguration,
  jsonWords,
  protocolLine,
  routingWords,
  type SpacecraftConfiguration,
} from "./api.ts";

/** Tab · Configuration (Investigate.md): what is it running, and what changed? Read-only in Ops. */
const props = defineProps<{ sc: FleetSpacecraft }>();
const scope = useMissionScope();
/** #1160: Edit in Setup is for those who may stage the change (config.stage, operate_mission). */
const canEdit = useCanStage(scope.value.mission.id);
const missionId = computed(() => scope.value.mission.id);
const config = useRemoteQuery(
  computed(() => ({ m: missionId.value, sc: props.sc.id })),
  (k, signal) => fetchConfiguration(k.m, k.sc, signal),
);
useMissionInvalidation(missionId, ["spacecraft", "catalog", "configuration"], config.refetch);

const at = (iso: string) => `${iso.slice(5, 10)} ${iso.slice(11, 16)}Z`;
const facts = (c: SpacecraftConfiguration) => [
  { key: "name", label: "Name", value: c.spacecraft.name },
  {
    key: "scid",
    label: "SCID",
    value: c.spacecraft.scid === null ? "not set" : String(c.spacecraft.scid),
    mono: true,
  },
  {
    key: "norad",
    label: "NORAD id",
    value: c.spacecraft.norad_id === null ? "not set" : String(c.spacecraft.norad_id),
    mono: true,
  },
  ...(c.spacecraft.plane === null
    ? []
    : [
        {
          key: "orbit",
          label: "Plane · slot",
          value: `P${String(c.spacecraft.plane).padStart(2, "0")}${c.spacecraft.slot === null ? "" : ` · slot ${String(c.spacecraft.slot).padStart(2, "0")}`}`,
          mono: true,
        },
      ]),
  {
    key: "catalog",
    label: "Catalog",
    value:
      c.catalog.running?.revision_number != null
        ? `rev ${c.catalog.running.revision_number}`
        : "not known",
    mono: true,
  },
];
</script>

<template>
  <ApRemote
    :state="config.state.value"
    loading-label="LOADING CONFIGURATION…"
    @retry="config.refetch"
  >
    <template #default="{ value: c }">
      <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-auto">
        <ApCallout v-if="c.spacecraft.archived" tone="stale">
          Archived {{ at(c.spacecraft.archived.at)
          }}{{ c.spacecraft.archived.by?.name ? ` by ${c.spacecraft.archived.by.name}` : "" }}. It
          isn't commanded or planned.
        </ApCallout>
        <div class="grid grid-cols-1 gap-3 console:grid-cols-2">
          <ApPanel index="G1" title="Running" flush>
            <template v-if="canEdit" #meta>
              <ApButton
                size="compact"
                variant="ghost"
                :to="{ name: 'setup.spacecraft.one', params: { spacecraftId: c.spacecraft.id } }"
                >Edit in Setup</ApButton
              >
            </template>
            <div class="flex flex-col gap-3 p-4">
              <p class="m-0">
                <RouterLink
                  v-if="c.profile"
                  :to="{ name: 'setup.profile', params: { profileId: c.profile.id } }"
                  class="text-readout hover:underline"
                  >{{ c.profile.name ?? "Profile"
                  }}{{ c.profile.version !== null ? ` · v${c.profile.version}` : "" }}</RouterLink
                >
                <span v-else class="text-caution-text">No spacecraft profile</span>
              </p>
              <!-- §11c parity (api c61444ede): what the pinned profile version runs. -->
              <p
                v-if="c.profile && (protocolLine(c.profile) || c.profile.lifecycle === 'deleted')"
                class="m-0 font-mono text-sm text-text-2"
              >
                {{ protocolLine(c.profile) ?? "" }}
                <span v-if="c.profile.lifecycle === 'deleted'" class="text-caution-text">
                  {{ protocolLine(c.profile) ? "· " : "" }}This profile version was deleted.</span
                >
              </p>
              <ApCallout v-if="catalogCaution(c.catalog)" tone="caution">
                {{ catalogCaution(c.catalog) }}
                <RouterLink :to="{ name: 'setup.readiness' }" class="text-readout underline"
                  >See Readiness.</RouterLink
                >
              </ApCallout>
              <ApKeyValue :items="facts(c)" />
            </div>
          </ApPanel>
          <ApPanel index="G2" title="Differs from its profile" flush class="max-md:hidden">
            <ApEmptyState
              v-if="c.overrides.length === 0"
              state="off"
              headline="Uses its profile as is."
            />
            <ul v-else class="m-0 list-none p-0">
              <ApListRow
                v-for="o in c.overrides"
                :key="o.path"
                :title="o.label ?? o.path"
                :sentence="o.reason ?? undefined"
                :meta="o.section ?? undefined"
              >
                <template #action>
                  <span class="font-mono text-sm whitespace-nowrap">
                    <span class="text-text-4">{{ jsonWords(o.profile_value_json, o.unit) }}</span>
                    →
                    <span class="text-readout">{{
                      jsonWords(o.spacecraft_value_json, o.unit)
                    }}</span>
                  </span>
                </template>
              </ApListRow>
            </ul>
          </ApPanel>
          <ApPanel index="G3" title="Routing" flush class="max-md:hidden">
            <ApEmptyState
              v-if="c.routing_rules.length === 0"
              state="off"
              headline="No routing applies."
            />
            <!-- ux review 6: plain rows (no status gutter), role said once. -->
            <ul v-else class="m-0 list-none p-0">
              <li
                v-for="r in c.routing_rules"
                :key="r.id"
                class="flex items-baseline gap-3 border-t border-hairline-faint px-4 py-2 first:border-t-0"
              >
                <span class="min-w-0 flex-1">
                  <span class="block text-readout">{{ routingWords(r) }}</span>
                  <span class="block text-sm text-text-3">{{
                    [r.purpose, r.direction, r.transport?.name].filter(Boolean).join(" · ")
                  }}</span>
                </span>
                <ApTag v-if="!r.enabled || !r.active" label="Inactive" state="off" />
              </li>
            </ul>
          </ApPanel>
          <ApPanel v-if="c.pending.length" index="G4" title="Pending" flush class="max-md:hidden">
            <ul class="m-0 list-none p-0">
              <template v-for="cs in c.pending" :key="cs.change_set_id">
                <ApListRow
                  v-for="ch in cs.changes"
                  :key="ch.id"
                  :title="`${cs.state.replaceAll('_', ' ')} · ${ch.summary}`"
                  :sentence="`${ch.author.name} · staged ${at(ch.staged_at)}${cs.base_revision !== null ? ` on r${cs.base_revision}` : ''}`"
                >
                  <template #action>
                    <ApButton size="compact" variant="ghost" :to="{ name: 'setup.changes' }"
                      >Changes</ApButton
                    >
                  </template>
                </ApListRow>
              </template>
            </ul>
          </ApPanel>
        </div>
        <ApPanel index="G5" title="Recent revisions" flush>
          <template #meta>
            <RouterLink
              :to="{ name: 'setup.revisions' }"
              class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
              >All revisions →</RouterLink
            >
          </template>
          <ApEmptyState
            v-if="c.recent_revisions.length === 0"
            state="off"
            headline="No applied revisions touch this spacecraft yet."
          />
          <ul v-else class="m-0 list-none p-0">
            <ApListRow
              v-for="r in c.recent_revisions"
              :key="r.revision"
              :sentence="r.summary ?? r.reason ?? `${r.entries.length} changes`"
            >
              <template #title>
                <RouterLink
                  :to="{ name: 'setup.revision', params: { revision: String(r.revision) } }"
                  class="max-md:hit-44 font-mono text-readout hover:underline"
                  >r{{ r.revision }}</RouterLink
                >
                <span class="ml-2 font-mono text-sm text-text-3"
                  >{{ at(r.applied_at) }} · {{ r.applied_by?.name ?? "Cadence" }}</span
                >
              </template>
            </ApListRow>
          </ul>
        </ApPanel>
      </div>
    </template>
  </ApRemote>
</template>
