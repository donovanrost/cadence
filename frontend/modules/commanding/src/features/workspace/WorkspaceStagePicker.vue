<script setup lang="ts">
import { ref } from "vue";
import CadencePopover from "@cadence/ui/CadencePopover.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import { stagesHref, type Directory, type StageQuery } from "@cadence/commanding/command-stages";
import type { Stage } from "@cadence/commanding/stage-workbench";
import type { WorkspaceOperation } from "./contracts";
const props = defineProps<{
  directory: Directory;
  stage: Stage | null;
  operation: WorkspaceOperation | null;
  disabled: boolean;
  browseStages: (query: Partial<StageQuery>) => Promise<void>;
  chooseStage: (id: string) => Promise<void>;
  createStage: (name: string, visibility: "private" | "shared") => Promise<void>;
  follow: (event: MouseEvent, href: string) => void;
}>();
const creating = ref(false),
  stageName = ref(""),
  stageVisibility = ref<"private" | "shared">("private");
const stageSearch = ref(props.directory.query.query);
async function selectStage(id: string, close: () => void) {
  await props.chooseStage(id);
  if (props.stage?.id === id) close();
}
async function create(close: () => void) {
  if (!stageName.value.trim()) return;
  await props.createStage(stageName.value, stageVisibility.value);
  if (props.operation?.status === "completed" && props.operation.event === "create_stage") {
    creating.value = false;
    stageName.value = "";
    close();
  }
}
</script>
<template>
  <CadencePopover
    id="command-workspace-stage-picker"
    identity="command-workspace-stage-picker"
    class="cw-stage-picker"
  >
    <template #trigger>
      <button type="button" data-overlay-trigger class="cw-stage-trigger">
        <span class="hero-queue-list cw-icon" aria-hidden="true" />
        <span class="cw-stage-trigger-label">{{ stage?.name || "Choose a stage" }}</span>
        <span class="hero-chevron-down cw-small-icon" aria-hidden="true" />
      </button>
    </template>
    <template #content="{ open, close }">
      <div v-if="open" class="cw-stage-menu" aria-labelledby="workspace-stage-picker-title">
        <div class="cw-stage-menu-heading">
          <strong id="workspace-stage-picker-title">Command stages</strong
          ><CadenceButton
            size="xs"
            variant="outline"
            :disabled="disabled"
            @click="creating = !creating"
            >{{ creating ? "Close" : "+ New stage" }}</CadenceButton
          >
        </div>
        <form
          v-if="creating"
          id="workspace-create-stage"
          class="cw-new-stage"
          @submit.prevent="create(close)"
        >
          <CadenceTextField
            id="workspace-stage-name"
            v-model="stageName"
            label="Stage name"
            placeholder="e.g. Pass preparation"
            :disabled="disabled"
            required
          /><label class="cw-field"
            >Visibility<select
              id="workspace-stage-visibility"
              v-model="stageVisibility"
              class="select select-bordered w-full"
              :disabled="disabled"
            >
              <option value="private">Private · your stage</option>
              <option value="shared">Shared · mission managers</option>
            </select></label
          ><CadenceButton
            id="workspace-create-stage-submit"
            type="submit"
            size="sm"
            variant="primary"
            :disabled="disabled || !stageName.trim()"
            >Create stage</CadenceButton
          >
        </form>
        <form class="cw-search" @submit.prevent="browseStages({ query: stageSearch, after: '' })">
          <input
            id="workspace-stage-search"
            v-model="stageSearch"
            type="search"
            aria-label="Find command stages"
            placeholder="Find a stage…"
            maxlength="240"
            :disabled="disabled"
          /><CadenceButton type="submit" size="xs" variant="quiet" :disabled="disabled"
            >Find</CadenceButton
          >
        </form>
        <div class="cw-stage-list">
          <button
            v-for="entry in directory.stages.entries"
            :key="entry.id"
            type="button"
            :data-workspace-stage="entry.id"
            :aria-pressed="stage?.id === entry.id"
            :disabled="disabled"
            @click="selectStage(entry.id, close)"
          >
            <strong>{{ entry.name }}</strong
            ><span>{{ entry.visibility }} · {{ entry.state.replaceAll("_", " ") }}</span
            ><span v-if="stage?.id === entry.id" aria-hidden="true">✓</span>
          </button>
          <p v-if="!directory.stages.entries.length" class="cw-empty">
            No stages in this view. Create one to begin preparing commands.
          </p>
        </div>
        <div class="cw-inline-actions">
          <CadenceButton
            v-if="directory.query.after"
            size="xs"
            variant="quiet"
            :disabled="disabled"
            @click="browseStages({ after: '' })"
            >First</CadenceButton
          ><CadenceButton
            v-if="directory.stages.next_after"
            size="xs"
            variant="quiet"
            :disabled="disabled"
            @click="browseStages({ after: directory.stages.next_after })"
            >Next 25 →</CadenceButton
          ><a
            :href="stagesHref(directory.context.missionId)"
            @click="follow($event, stagesHref(directory.context.missionId))"
            >All stages</a
          >
        </div>
      </div>
    </template></CadencePopover
  >
</template>
