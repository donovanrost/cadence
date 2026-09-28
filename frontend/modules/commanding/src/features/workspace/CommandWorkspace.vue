<script setup lang="ts">
import { targetLabel } from "../../shared/command-draft/target-label";
import { computed, nextTick, ref } from "vue";
import type { OpsPagePort, LiveOpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceWorkspaceLayout from "@cadence/ui/CadenceWorkspaceLayout.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import WorkspaceFleet from "./WorkspaceFleet.vue";
import WorkspaceCatalog from "./WorkspaceCatalog.vue";
import WorkspacePreparation from "./WorkspacePreparation.vue";
import WorkspaceEnqueueResult from "./WorkspaceEnqueueResult.vue";
import WorkspaceShelf from "./WorkspaceShelf.vue";
import WorkspaceStagePicker from "./WorkspaceStagePicker.vue";
import { useCommandWorkspace } from "./useCommandWorkspace";
import type { WorkspacePreparation as PreparationPage, WorkspaceObservation } from "./contracts";
import "./workspace.css";
const props = defineProps<{
  page: PreparationPage;
  port: OpsPagePort;
  readPort: LiveOpsPageReadPort;
}>();
const emit = defineEmits<{ observe: [page: WorkspaceObservation] }>();
const {
  page,
  context,
  submitting,
  browsing,
  reviewing,
  validating,
  validationEpoch,
  syncing,
  syncFailed,
  writesDisabled,
  feedback,
  accessLost,
  operation,
  enqueueResult,
  command,
  draft,
  names,
  selection,
  itemSelection,
  targetPreview,
  queuePreview,
  batchPreview,
  confirmed,
  dockOpen,
  setDraft,
  select,
  selectVisible,
  clearSelection,
  browseCatalog,
  targetResults,
  commandResults,
  searchTargets,
  searchCommands,
  loadMoreTargets,
  loadMoreCommands,
  retryTargets,
  retryCommands,
  browseItems,
  browseStages,
  chooseStage,
  prepare,
  chooseItem,
  reviewBatch,
  saveTargets,
  enqueue,
  submit,
  createStage,
  cancelItem,
  moveItem,
  refresh,
  follow,
} = useCommandWorkspace(props.page, props.port, props.readPort, (page) => emit("observe", page));
const stage = computed(() => page.value.workbench?.stage ?? null);
const stageOperation = computed(() =>
  operation.value?.event === "enqueue" ? null : operation.value,
);
const catalogPane = ref<InstanceType<typeof WorkspaceCatalog>>();
async function closePreparation() {
  const id = command.value?.id;
  await browseCatalog({ command: "" });
  await nextTick();
  if (!command.value && id) catalogPane.value?.focusCommand(id);
}
const targetNames = computed(() =>
  Object.fromEntries(
    [...targetResults.value.entries, ...selection.value].map((target) => [
      target.id,
      targetLabel(target),
    ]),
  ),
);
const commandNames = computed(() =>
  Object.fromEntries(
    [...commandResults.value.entries, ...(command.value ? [command.value] : [])].map((item) => [
      item.id,
      item.display_name || item.name,
    ]),
  ),
);
</script>
<template>
  <div id="command-workspace" class="command-workspace">
    <CadencePageHeading><template #title>Commanding</template></CadencePageHeading>
    <p v-if="accessLost" role="alert" class="cw-notice">
      Command preparation is unavailable with your current access. Reopen Ops to read the current
      mission view.
    </p>
    <p v-if="syncFailed && !accessLost" id="workspace-sync-error" role="status" class="cw-notice">
      Live updates are interrupted. Your preparation is still here.
      <CadenceButton
        id="workspace-retry-sync"
        size="xs"
        variant="quiet"
        :loading="syncing"
        @click="refresh"
        >Retry updates</CadenceButton
      >
    </p>
    <p v-if="feedback" id="workspace-feedback" role="alert" class="cw-notice">{{ feedback }}</p>
    <WorkspaceEnqueueResult
      v-if="enqueueResult && !command"
      :operation="enqueueResult"
      :pending="submitting"
      :checking="syncing"
      @check-result="refresh"
    />
    <CadenceWorkspaceLayout
      v-if="!accessLost"
      id="commanding"
      :storage-id="`cadence-commanding-${context.organizationId}-${context.missionId}-v1`"
      :inspector="!!command"
      v-model:dock="dockOpen"
      :dock-title="stage?.name || 'Command shelf'"
      dock-icon="hero-queue-list"
      dock-expand-label="Expand command shelf"
      primary-resize-label="Resize spacecraft and command catalog"
      inspector-resize-label="Resize command catalog and preparation"
      dock-resize-label="Resize preparation and command shelf"
    >
      <template #primary
        ><WorkspaceFleet
          :catalog="page.catalog"
          :results="targetResults"
          :selected="selection"
          :names="names"
          :disabled="accessLost"
          @toggle="select"
          @clear="clearSelection"
          @select-visible="selectVisible"
          @search="searchTargets"
          @load-more="loadMoreTargets"
          @retry="retryTargets"
      /></template>
      <template #secondary
        ><WorkspaceCatalog
          ref="catalogPane"
          :catalog="page.catalog"
          :results="commandResults"
          :selected-count="selection.length"
          :disabled="accessLost"
          @browse="browseCatalog"
          @search="searchCommands"
          @load-more="loadMoreCommands"
          @retry="retryCommands"
      /></template>
      <template #inspector
        ><WorkspacePreparation
          v-if="command"
          :key="command.id"
          :command="command"
          :targets="selection"
          :spacecraft-names="names"
          :draft="draft"
          :stage="stage"
          :preview="targetPreview"
          :queue-preview="queuePreview"
          :disabled="accessLost"
          :validating="validating"
          :action-disabled="writesDisabled"
          :validation-error="!!feedback"
          :validation-context="
            JSON.stringify([
              page.catalog?.basis,
              page.catalog?.target_bases,
              validationEpoch,
              browsing,
            ])
          "
          @close="closePreparation"
          @update:draft="setDraft"
          @remove="select"
          @prepare="prepare"
          @save="saveTargets"
          @enqueue="enqueue"
          ><template #result
            ><WorkspaceEnqueueResult
              v-if="enqueueResult"
              :operation="enqueueResult"
              :pending="submitting"
              :checking="syncing"
              @check-result="refresh" /></template></WorkspacePreparation
      ></template>
      <template #dock
        ><WorkspaceShelf
          :mission="context.missionId"
          :workbench="page.workbench"
          :action-disabled="writesDisabled"
          :reviewing="reviewing || browsing"
          :selection="itemSelection"
          :preview="batchPreview"
          v-model:confirmed="confirmed"
          :operation="stageOperation"
          :checking-result="submitting || syncing"
          :disabled="accessLost"
          :target-names="targetNames"
          :command-names="commandNames"
          :follow="follow"
          @choose="chooseItem"
          @browse="browseItems"
          @review="reviewBatch"
          @submit="submit"
          @minimize="dockOpen = false"
          @check-result="refresh"
          @cancel="cancelItem"
          @move="moveItem"
          ><template #stage-picker
            ><WorkspaceStagePicker
              :directory="page.directory"
              :action-disabled="writesDisabled"
              :stage="stage"
              :operation="stageOperation"
              :disabled="accessLost"
              :browse-stages="browseStages"
              :choose-stage="chooseStage"
              :create-stage="createStage"
              :follow="follow" /></template></WorkspaceShelf
      ></template>
      <template #dock-summary> Stage {{ page.workbench?.items.entries.length ?? 0 }} </template>
    </CadenceWorkspaceLayout>
  </div>
</template>
