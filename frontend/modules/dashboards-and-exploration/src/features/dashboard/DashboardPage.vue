<script setup lang="ts">
import { computed, ref, useId, watch } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceDialog from "@cadence/ui/CadenceDialog.vue";
import CadenceNoticeFrame from "@cadence/ui/CadenceNoticeFrame.vue";
import CadenceEmptyStateFrame from "@cadence/ui/CadenceEmptyStateFrame.vue";
import type { LayoutEdit } from "./contracts";
import { diagnosticsHref } from "./links";
import type { Panel } from "./panels";
import { ago, useNow } from "./useNow";
import { useDashboardPage, type DashboardPageProps } from "./useDashboardPage";
import DashboardBoard from "./DashboardBoard.vue";
import DashboardHeader from "./DashboardHeader.vue";
import DashboardPanels from "./DashboardPanels.vue";
import DashboardToolbar from "./DashboardToolbar.vue";
import EditBar from "./EditBar.vue";

defineOptions({ inheritAttrs: false });
const props = defineProps<DashboardPageProps>();
const state = useDashboardPage(props);
const { page, snapshot, editing, dirty, pending, notice, paused } = state;
const now = useNow();
const panel = ref<Panel | null>(null);
const instance = `dashboard-${useId().replaceAll(/[^a-zA-Z0-9_-]/g, "-")}`;

const outline = computed(() => (page.value.mode === "edit" ? page.value.edit.outline : null));
const refreshMs = computed(() => page.value.live.refresh_ms ?? 2_000);
const updatedAt = computed(() => Date.parse(page.value.resolved_at));
// The scope Phoenix resolved, not the raw URL: an inadmissible selection never shows as chosen.
const spacecraft = computed(() => {
  const context = snapshot.value?.context;
  return context?.scope_kind === "spacecraft" ? (context.scope_ids[0] ?? null) : null;
});

// Drives the host's live dot: a pulse on arrival, warning when refreshes stop.
const receiving = ref(false);
watch(updatedAt, () => {
  receiving.value = true;
  setTimeout(() => (receiving.value = false), 700);
});
const streamState = computed(() => {
  if (!page.value.live.active) return undefined;
  if (paused.value) return "paused";
  if (now.value - updatedAt.value > refreshMs.value * 5) return "delayed";
  return receiving.value ? "receiving" : "following";
});

// Leaving edit mode with unsaved changes asks first, like Grafana's Exit edit.
const exiting = ref(false);
function requestExit() {
  if (dirty.value) exiting.value = true;
  else state.exitEdit();
}
async function discardAndExit() {
  exiting.value = false;
  await state.discardAndExit();
}

// Someone else saved: offer to replay my edits on their version. A dismissed
// prompt stays dismissed until their next save.
const dismissedAt = ref<number | null>(null);
const conflictOpen = computed(
  () =>
    page.value.mode === "edit" &&
    page.value.edit.conflict &&
    dismissedAt.value !== page.value.saved.version,
);
const dismissConflict = () => (dismissedAt.value = page.value.saved.version);
async function continueEditing() {
  dismissConflict();
  await state.rebase();
}
async function discardConflict() {
  dismissConflict();
  await state.discard();
}

// Drags report often; only the newest layout waits behind an in-flight change.
let queuedLayout: LayoutEdit[] | null = null;
async function stageLayout(layouts: LayoutEdit[]) {
  if (pending.value) {
    queuedLayout = layouts;
    return;
  }
  await state.stage("layout", { layouts });
  const next = queuedLayout;
  queuedLayout = null;
  if (next) await stageLayout(next);
}
</script>

<template>
  <div
    id="ops-dashboard-show-page"
    class="space-y-3"
    :data-dashboard-live-stream-state="streamState"
    :aria-busy="pending"
  >
    <DashboardHeader
      :name="snapshot?.name ?? outline?.name ?? 'Dashboard'"
      :description="snapshot?.description ?? null"
      :author="page.author"
      :editing="editing"
      :dirty="dirty"
      :conflict="page.mode === 'edit' && page.edit.conflict"
      :pending="pending"
      :base="state.base.value"
      :diagnostics-href="diagnosticsHref(state.base.value, snapshot)"
      @edit="state.enterEdit"
      @exit="requestExit"
      @save="panel = { kind: 'save' }"
      @copy="panel = { kind: 'copy' }"
      @versions="panel = { kind: 'versions' }"
    >
      <DashboardToolbar
        v-if="snapshot"
        :context="snapshot.context"
        :scope-options="page.scope_options"
        :spacecraft="spacecraft"
        :live-capable="page.live.active"
        :paused="paused"
        :updated-ago="ago(now - updatedAt)"
        :now="now"
        @time="state.setTime"
        @spacecraft="state.setSpacecraft"
        @pause="state.togglePause"
      />
    </DashboardHeader>
    <EditBar
      v-if="outline"
      :dirty="dirty"
      :pending="pending"
      :widgets="outline.placements.length"
      :sections="outline.sections.length"
      @add-widget="panel = { kind: 'widget', id: null }"
      @add-section="panel = { kind: 'section', id: null }"
      @details="panel = { kind: 'details' }"
    />
    <CadenceNoticeFrame
      v-if="notice"
      :tone="notice.tone === 'success' || notice.tone === 'info' ? 'info' : 'warning'"
      role="status"
    >
      {{ notice.text }}
    </CadenceNoticeFrame>
    <CadenceEmptyStateFrame v-if="!snapshot">
      <template #title>Not published yet</template>
      <template #description
        >This dashboard becomes available here once an author publishes it.</template
      >
    </CadenceEmptyStateFrame>
    <CadenceEmptyStateFrame v-else-if="!snapshot.placements.length">
      <template #title>No widgets yet</template>
      <template #description>
        {{
          editing
            ? "Add a widget to start building this dashboard."
            : "This dashboard has no widgets."
        }}
      </template>
      <template v-if="page.author" #action>
        <CadenceButton
          v-if="editing"
          variant="primary"
          size="sm"
          @click="panel = { kind: 'widget', id: null }"
          >Add widget</CadenceButton
        >
        <CadenceButton v-else variant="primary" size="sm" @click="state.enterEdit"
          >Edit dashboard</CadenceButton
        >
      </template>
    </CadenceEmptyStateFrame>
    <DashboardBoard
      v-else
      :snapshot="snapshot"
      :editing="editing"
      :live="page.live.active && !paused"
      :now="now"
      :stale-after-ms="Math.max(refreshMs * 5, 30_000)"
      :instance="instance"
      @layout="stageLayout"
      @inspect="(placement) => (panel = { kind: 'inspect', placement })"
      @configure="(id) => (panel = { kind: 'widget', id })"
      @remove="(id) => state.stage('remove_widget', { placement_id: id })"
      @edit-section="(id) => (panel = { kind: 'section', id })"
      @move-section="(id, direction) => state.stage('move_section', { section_id: id, direction })"
      @remove-section="(id) => state.stage('remove_section', { section_id: id })"
    />
    <DashboardPanels v-model="panel" :state="state" :outline="outline" />
    <CadenceDialog
      :open="exiting"
      tone="danger"
      title="Discard unsaved changes?"
      description="You have unsaved changes to this dashboard. Leaving edit mode discards them."
      @update:open="(open) => (exiting = open)"
    >
      <template #actions>
        <CadenceButton variant="quiet" size="sm" @click="exiting = false">Cancel</CadenceButton>
        <CadenceButton variant="danger" size="sm" :loading="pending" @click="discardAndExit">
          Discard
        </CadenceButton>
      </template>
    </CadenceDialog>
    <CadenceDialog
      :open="conflictOpen"
      title="Dashboard changed"
      description="Someone else saved this dashboard while you were editing. Continue to reapply your changes on top of their version, or discard yours."
      @update:open="(open) => !open && dismissConflict()"
    >
      <template #actions>
        <CadenceButton variant="quiet" size="sm" :disabled="pending" @click="discardConflict">
          Discard my changes
        </CadenceButton>
        <CadenceButton variant="primary" size="sm" :loading="pending" @click="continueEditing">
          Continue editing
        </CadenceButton>
      </template>
    </CadenceDialog>
  </div>
</template>
