<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import type { SpacecraftId } from "@/api/index.ts";
import { codeOf, useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  ApBreadcrumb,
  ApButton,
  ApEmptyState,
  ApPageHeader,
  ApRemote,
  ApSelect,
  ApTabLinks,
  ApTag,
  type ApCrumb,
  type ApTabLink,
} from "@/ui";
import { fetchWorkspace, sections, type ConfigurationSnapshot } from "./api.ts";
import ComparisonTable from "./ComparisonTable.vue";
import SettingsPanel from "./SettingsPanel.vue";
import SetupSteps from "./SetupSteps.vue";
import SwitchesPanel from "./SwitchesPanel.vue";
import { changesCount, readRefusal, statusTag, versionsLine } from "./words.ts";

/**
 * (B) ux U94: Setup › Spacecraft › EARENDIL-004 › Configuration, the host's workspace in the
 * console. Read side only (lead): the draft, the active entry, the switches and the comparison.
 * Saving and sending come once api's write routes exist.
 */
const props = defineProps<{ spacecraftId: SpacecraftId | null }>();
const route = useRoute("setup.spacecraft.configuration");
const router = useRouter();
const scope = useMissionScope();
const section = computed(
  () => sections.find((s) => s === route.params.section) ?? ("overview" as const),
);
const key = computed(() =>
  props.spacecraftId
    ? {
        missionId: scope.value.mission.id,
        spacecraftId: props.spacecraftId,
        section: section.value,
      }
    : null,
);
const { state, refetch } = useRemoteQuery(key, fetchWorkspace);
useMissionInvalidation(
  computed(() => scope.value.mission.id),
  ["spacecraft", "configuration", "activations"],
  refetch,
);

const LABELS = {
  overview: "Overview",
  catalog: "Catalog & applications",
  communications: "Communications",
  changes: "Changes",
} as const;
function links(s: ConfigurationSnapshot): readonly ApTabLink[] {
  // U94: the Changes tab counts what differs ("Changes 2").
  const count = changesCount(s);
  return sections.map((key) => {
    const to = {
      name: "setup.spacecraft.configuration" as const,
      params: { spacecraftId: s.spacecraft_id, section: key },
    };
    return key === "changes" && count !== undefined
      ? { key, label: LABELS[key], to, count }
      : { key, label: LABELS[key], to };
  });
}
const name = computed(() =>
  state.value.status === "ready" ? state.value.value.name : "Spacecraft",
);
const crumbs = computed((): readonly ApCrumb[] => {
  const list: ApCrumb[] = [{ label: "Spacecraft", to: { name: "setup.spacecraft" } }];
  if (props.spacecraftId)
    list.push({
      label: name.value,
      to: { name: "setup.spacecraft.one", params: { spacecraftId: props.spacecraftId } },
    });
  list.push({ label: "Configuration" });
  return list;
});
/** The craft switcher (the host's): the same section on another craft. */
function switchTo(id: string) {
  if (id && id !== props.spacecraftId)
    void router.push({
      name: "setup.spacecraft.configuration",
      params: { spacecraftId: id, section: section.value },
    });
}
/** U94: the snapshot's own refusals read as a state, not a Retry. */
const refusal = computed(() =>
  state.value.status === "failed" ? readRefusal(codeOf(state.value.error)) : null,
);
const craftOptions = (s: ConfigurationSnapshot) =>
  s.fleet.map((c) => ({ value: c.id, label: c.name }));
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApEmptyState v-if="refusal" state="off" :headline="refusal.text">
      <ApButton v-if="refusal.comms" size="compact" :to="{ name: 'setup.comms' }"
        >Open Comms</ApButton
      >
    </ApEmptyState>
    <ApRemote v-else :state="state" loading-label="Loading configuration…" @retry="refetch">
      <template #default="{ value }">
        <ApPageHeader
          :title="value.active ? `${value.name}'s configuration` : `Set up ${value.name}`"
          size="reading"
        >
          <template #status>
            <ApTag :state="statusTag(value).state" :label="statusTag(value).label" />
          </template>
        </ApPageHeader>
        <!-- Phone order (ux): title, tag, versions, then the switcher. -->
        <div class="flex flex-wrap items-center justify-between gap-3">
          <p class="m-0 font-mono text-sm text-text-2">{{ versionsLine(value) ?? "" }}</p>
          <ApSelect
            v-if="value.fleet.length > 1"
            :model-value="value.spacecraft_id"
            label="Spacecraft"
            hidden-label
            size="compact"
            :options="craftOptions(value)"
            @update:model-value="switchTo"
          />
        </div>
        <ApTabLinks :links="links(value)" :active="section" label="Configuration sections" />
        <SetupSteps :snapshot="value" />
        <template v-if="section === 'changes'">
          <ComparisonTable :snapshot="value" />
        </template>
        <SettingsPanel
          v-else-if="section === 'communications'"
          :snapshot="value"
          show="communications"
        />
        <div v-else class="grid grid-cols-1 gap-3 console:grid-cols-[minmax(0,1fr)_360px]">
          <SettingsPanel :snapshot="value" :show="section === 'overview' ? 'all' : 'catalog'" />
          <SwitchesPanel :snapshot="value" />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
