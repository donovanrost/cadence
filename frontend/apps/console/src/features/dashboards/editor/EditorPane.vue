<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApEmptyState } from "@/ui";
import type { DashboardView } from "../api.ts";
import EditBoard from "./EditBoard.vue";
import type { SourceWarning } from "./contracts.ts";
import EditCallouts from "./EditCallouts.vue";
import SaveSheet from "./SaveSheet.vue";
import SectionSheet from "./SectionSheet.vue";
import WidgetSheet from "./WidgetSheet.vue";
import type { useEditSession } from "./useEditSession.ts";

/** The board in edit mode with its sheets. The screen's header actions drive it through `expose`. */
const props = defineProps<{
  session: ReturnType<typeof useEditSession>;
  view: DashboardView;
  missionId: MissionId;
}>();
const emit = defineEmits<{ saved: [warnings: readonly SourceWarning[]] }>();
const widgetSheet = ref<InstanceType<typeof WidgetSheet> | null>(null);
const saveSheet = ref<InstanceType<typeof SaveSheet> | null>(null);
const sectionSheet = ref<InstanceType<typeof SectionSheet> | null>(null);
const staged = computed(() => props.session.staged.value);
const retiredLibrary = computed(
  () => staged.value?.outline.placements.some((p) => p.library?.retired === true) ?? false,
);
const sections = computed(
  () => staged.value?.outline.sections.map((s) => ({ id: s.id, title: s.title })) ?? [],
);

async function onSave(input: { message: string; defaults: { time: boolean; scope: boolean } }) {
  const result = await props.session.save(input);
  saveSheet.value?.close();
  if (result.ok) emit("saved", result.warnings);
}
defineExpose({
  add: () => widgetSheet.value?.openFor(null),
  addSection: () => sectionSheet.value?.openFor(null),
  save: () => saveSheet.value?.open(),
});
</script>

<template>
  <EditCallouts
    :conflict="session.conflict.value"
    :notice="session.notice.value"
    :busy="session.busy.value"
    :resumed="session.resumed.value"
    :retired-library="retiredLibrary"
    @continue="session.continueEditing"
    @discard-mine="session.discardMine"
  />
  <EditBoard
    v-if="staged"
    :preview="staged"
    @stage="session.stage"
    @edit="(p, sectionId) => widgetSheet?.openFor(p, sectionId)"
    @edit-section="sectionSheet?.openFor($event)"
  />
  <ApEmptyState v-else headline="Opening the editor…" />
  <WidgetSheet
    ref="widgetSheet"
    :mission-id="missionId"
    :dashboard-id="view.dashboard.id"
    :base-version="session.draft.value?.baseVersion ?? view.dashboard.current_version ?? 0"
    :sections="sections"
    :spacecraft="view.scope_options"
    @stage="session.stage"
  />
  <SectionSheet ref="sectionSheet" @stage="session.stage" />
  <SaveSheet
    ref="saveSheet"
    :changes="session.changes.value"
    :previewing="session.previewing.value"
    :busy="session.busy.value"
    :has-scope="view.scope_options.length > 0"
    @save="onSave"
  />
</template>
