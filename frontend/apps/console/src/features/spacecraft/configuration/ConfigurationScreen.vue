<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { onBeforeRouteLeave, useRoute, useRouter } from "vue-router";
import type { SpacecraftId } from "@/api/index.ts";
import { codeOf, useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import {
  ApBreadcrumb,
  ApButton,
  ApPageHeader,
  ApRemote,
  ApSelect,
  ApTabLinks,
  ApTag,
  OutcomeCallout,
  type ApCrumb,
  type ApTabLink,
} from "@/ui";
import ConfirmDialog from "@/features/commands/compose/ConfirmDialog.vue";
import { fetchWorkspace, sections, type ConfigurationSnapshot } from "./api.ts";
import ConfigurationBody from "./ConfigurationBody.vue";
import ConflictPanel from "./ConflictPanel.vue";
import DraftBar from "./DraftBar.vue";
import { discardQuestion, leaveBody } from "./draft-words.ts";
import { useConfigurationDraft } from "./useConfigurationDraft.ts";
import { changesCount, readRefusal, statusTag, versionsLine } from "./words.ts";

/**
 * (B) ux U94: Setup › Spacecraft › EARENDIL-004 › Configuration, the host's workspace in the
 * console: the draft, the active entry, the switches and the comparison. #595a: one draft across
 * the tabs, saved with `Save draft`; sending it for activation is #595c.
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
const draft = useConfigurationDraft(
  key,
  () => (state.value.status === "ready" ? state.value.value : null),
  refetch,
);
/** Framing sizes that don't read as numbers (Save waits for them). */
const invalid = ref(0);
const errors = computed(() => draft.failure.value?.fields ?? {});
/** #595a: who can change it; the server refuses anyone else (`forbidden`). */
const editable = (s: ConfigurationSnapshot) => s.approval.can_request;

// mms-ux (#595a): leaving with unsaved edits asks first; moving between this craft's tabs doesn't.
const leaveDialog = ref<InstanceType<typeof ConfirmDialog> | null>(null);
onBeforeRouteLeave(async (to) => {
  if (!draft.dirty.value) return true;
  if (
    to.name === "setup.spacecraft.configuration" &&
    to.params["spacecraftId"] === props.spacecraftId
  )
    return true;
  return (await leaveDialog.value?.ask()) === true;
});
const onUnload = (e: BeforeUnloadEvent) => {
  if (draft.dirty.value) e.preventDefault();
};
onMounted(() => window.addEventListener("beforeunload", onUnload));
onBeforeUnmount(() => window.removeEventListener("beforeunload", onUnload));
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
  // ux #349/#352: the middle crumb only once the craft's name has arrived (not while loading, not
  // when the read failed).
  if (props.spacecraftId && state.value.status === "ready")
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
/** The PUT's fresh answer until the next read arrives, else the read (#595a). */
const snap = (value: ConfigurationSnapshot) => draft.snapshot.value ?? value;
const craftOptions = (s: ConfigurationSnapshot) =>
  s.fleet.map((c) => ({ value: c.id, label: c.name }));
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <!-- U98, ux #349: the read's refusal is the page's empty state, a body sentence, no mark. -->
    <div v-if="refusal" role="status" class="flex flex-col items-start gap-2 px-4 py-6">
      <p class="m-0 max-w-[60ch] text-base leading-[1.55] text-text-3">{{ refusal.text }}</p>
      <ApButton v-if="refusal.comms" size="compact" :to="{ name: 'setup.comms' }"
        >Open Comms</ApButton
      >
    </div>
    <ApRemote v-else :state="state" loading-label="Loading configuration…" @retry="refetch">
      <template #default="{ value }">
        <ApPageHeader
          :title="value.active ? `${value.name}'s configuration` : `Set up ${value.name}`"
          size="reading"
        >
          <template #status>
            <ApTag v-bind="statusTag(snap(value), draft.dirty.value)" />
          </template>
          <ApSelect
            v-if="value.fleet.length > 1 && !versionsLine(snap(value))"
            :model-value="value.spacecraft_id"
            label="Spacecraft"
            hidden-label
            size="compact"
            :options="craftOptions(value)"
            @update:model-value="switchTo"
          />
        </ApPageHeader>
        <!-- Phone order (ux): title, tag, versions, then the switcher. -->
        <div
          v-if="versionsLine(snap(value))"
          class="flex flex-wrap items-center justify-between gap-3"
        >
          <p class="m-0 font-mono text-sm text-text-2">{{ versionsLine(snap(value)) }}</p>
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
        <ApTabLinks :links="links(snap(value))" :active="section" label="Configuration sections" />
        <ConflictPanel
          v-if="draft.conflict.value && draft.doc.value"
          :snapshot="snap(value)"
          :saved="draft.conflict.value"
          :mine="draft.doc.value"
          @use-saved="draft.useSaved"
          @keep-mine="draft.keepMine"
        />
        <DraftBar
          v-else
          :dirty="draft.dirty.value"
          :saving="draft.saving.value"
          :failure="draft.failure.value"
          :invalid="invalid"
          :discard-question="discardQuestion(snap(value))"
          @save="draft.save"
          @discard="draft.discard"
        />
        <OutcomeCallout v-if="draft.saved.value" :outcome="draft.saved.value" />
        <ConfigurationBody
          :snapshot="snap(value)"
          :doc="draft.doc.value ?? value.document"
          :section="section"
          :workspace="key"
          :editable="editable(value)"
          :errors="errors"
          @edit="draft.edit"
          @invalid="invalid = $event"
        />
      </template>
    </ApRemote>
    <ConfirmDialog
      ref="leaveDialog"
      question="Leave without saving?"
      :body="leaveBody(name)"
      confirm="Leave"
      cancel="Stay"
    />
  </div>
</template>
