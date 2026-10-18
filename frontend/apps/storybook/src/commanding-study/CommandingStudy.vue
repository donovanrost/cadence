<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceWorkspaceLayout from "@cadence/ui/CadenceWorkspaceLayout.vue";
import FleetSelection from "./FleetSelection.vue";
import CommandPreparation from "./CommandPreparation.vue";
import StagingShelf from "./StagingShelf.vue";
import { commands } from "./fixtures";
import { useCommandingStudy } from "./state";
import "./commanding-study.css";

const props = withDefaults(
  defineProps<{ initial?: "empty" | "preparing" | "staged" | "incompatible" }>(),
  { initial: "empty" },
);
const {
  selectedIds,
  selected,
  command,
  draft,
  incompatible,
  canStage,
  staged,
  execution,
  shelf,
  shelfOpen,
  reviewing,
  confirmed,
  feedback,
  toggleTarget,
  chooseCommand,
  setValue,
  setOverride,
  stage,
  remove,
  move,
  review,
  releaseSimulation,
  advanceSimulation,
} = useCommandingStudy();
if (props.initial !== "empty") {
  selectedIds.value = ["KESTREL-01", "KESTREL-02", "KESTREL-05"];
  chooseCommand("SET_TLM_RATE");
}
if (props.initial === "staged") {
  setOverride("KESTREL-02", "10 s");
  stage();
}
if (props.initial === "incompatible") {
  selectedIds.value = ["KESTREL-01", "KESTREL-07"];
  chooseCommand("CAPTURE_IMAGE");
}
const search = ref("");
const subsystem = ref("All systems");
const visibleCommands = computed(() =>
  commands.filter(
    (item) =>
      (subsystem.value === "All systems" || item.subsystem === subsystem.value) &&
      (item.id + " " + item.title).toLowerCase().includes(search.value.toLowerCase()),
  ),
);
function minimizeShelf() {
  shelfOpen.value = false;
}
</script>
<template>
  <div class="commanding-study">
    <div class="study-design-banner">
      <span><strong>DESIGN STUDY</strong> · Sample mission data</span
      ><span>Local simulation · no spacecraft connection</span>
    </div>
    <header class="study-app-header">
      <div class="study-app-identity">
        <span class="study-brand" aria-hidden="true">C</span><strong>CADENCE</strong
        ><span class="study-header-divider" /><span>Kestrel</span><span class="study-slash">/</span
        ><span>Operations</span>
      </div>
      <div class="study-header-context">
        <span class="study-mode"
          ><span class="hero-beaker study-icon-small" aria-hidden="true" />Simulation</span
        ><time datetime="2026-09-12T14:32:07Z">14:32:07 UTC</time
        ><span class="study-avatar" aria-label="Sample operator">OP</span>
      </div>
    </header>
    <main class="study-main" aria-label="Commanding design study">
      <div class="study-workspace-toolbar">
        <div class="study-title">
          <span class="hero-command-line study-icon" aria-hidden="true" />
          <h1>Commanding</h1>
          <span class="study-workspace-label">Fleet workspace</span>
        </div>
        <div class="study-toolbar-actions">
          <span v-if="selected.length" id="study-selected-count" class="study-selection-summary"
            >{{ selected.length }} spacecraft<span class="study-separator-dot">·</span
            >{{ selected.length }} OBC endpoints</span
          >
          <span v-else class="study-fine-print">Select spacecraft to begin</span>
        </div>
      </div>
      <div class="study-workspace">
        <CadenceWorkspaceLayout
          id="study"
          storage-id="cadence-commanding-study-layout-v2"
          :inspector="!!command"
          v-model:dock="shelfOpen"
          dock-title="Command shelf"
          dock-expand-label="Expand command shelf"
          primary-resize-label="Resize spacecraft and command catalog"
          inspector-resize-label="Resize command catalog and preparation"
          dock-resize-label="Resize preparation and command shelf"
        >
          <template #primary>
            <FleetSelection
              :selected="selectedIds"
              @toggle="toggleTarget"
              @select="selectedIds = $event"
            />
          </template>
          <template #secondary>
            <section class="study-pane study-catalog" aria-labelledby="study-catalog-title">
              <header class="study-pane-heading">
                <h2 id="study-catalog-title">
                  <span class="hero-command-line study-icon" aria-hidden="true" />Command catalog
                </h2>
                <span class="study-count">{{ visibleCommands.length }}</span>
              </header>
              <div class="study-search">
                <span class="hero-magnifying-glass study-icon" aria-hidden="true" /><input
                  id="study-command-search"
                  v-model="search"
                  type="search"
                  aria-label="Find commands"
                  placeholder="Find a command or operation…"
                />
              </div>
              <div class="study-system-filters" role="group" aria-label="Command subsystem">
                <button
                  v-for="system in ['All systems', 'C&DH', 'ADCS', 'Payload']"
                  :key="system"
                  type="button"
                  :aria-pressed="subsystem === system"
                  @click="subsystem = system"
                >
                  {{ system }}
                </button>
              </div>
              <div v-if="!selected.length" class="study-catalog-context">
                <span class="hero-cursor-arrow-rays study-icon" aria-hidden="true" />
                <p>Select spacecraft to see command compatibility and begin preparation.</p>
              </div>
              <div v-else class="study-catalog-context">
                <span class="hero-square-3-stack-3d study-icon" aria-hidden="true" />
                <p>
                  Compatibility across
                  <strong>{{ selected.length }} selected spacecraft</strong>
                </p>
              </div>
              <div class="study-scroll study-command-list">
                <button
                  v-for="item in visibleCommands"
                  :key="item.id"
                  type="button"
                  class="study-command"
                  :data-command="item.id"
                  :aria-pressed="command?.id === item.id"
                  :disabled="!selected.length"
                  @click="chooseCommand(item.id)"
                >
                  <span :class="[item.icon, 'study-command-icon']" aria-hidden="true" />
                  <span class="study-command-copy"
                    ><code>{{ item.id }}</code
                    ><strong>{{ item.title }}</strong>
                    <span class="study-command-meta"
                      >{{ item.subsystem }}<span class="study-separator-dot">·</span
                      >{{ item.choices.length ? "1 setting" : "No arguments"
                      }}<span v-if="item.hazardous" class="study-hazard-label"
                        ><span
                          class="hero-exclamation-triangle study-icon-small"
                          aria-hidden="true"
                        />Hazardous</span
                      ></span
                    >
                  </span>
                  <span
                    v-if="selected.length"
                    class="study-command-availability"
                    :class="{
                      'is-partial': selected.some((target) => !target.supports.includes(item.id)),
                    }"
                  >
                    <span
                      >{{
                        selected.filter((target) => target.supports.includes(item.id)).length
                      }}/{{ selected.length }}</span
                    >
                    <span class="hero-chevron-right study-icon-small" aria-hidden="true" />
                  </span>
                </button>
                <p v-if="!visibleCommands.length" class="study-empty">
                  No commands match this search.
                </p>
              </div>
              <footer class="study-pane-footer">
                <span>Mission model catalog</span><span>5 definitions</span>
              </footer>
            </section>
          </template>
          <template #inspector>
            <CommandPreparation
              v-if="command"
              :command="command"
              :targets="selected"
              :incompatible="incompatible"
              :draft="draft"
              :can-stage="canStage"
              @close="command = null"
              @value="setValue"
              @override="setOverride"
              @remove-target="toggleTarget"
              @stage="stage"
            />
          </template>
          <template #dock>
            <StagingShelf
              :staged="staged"
              :execution="execution"
              :active="shelf"
              :reviewing="reviewing"
              :confirmed="confirmed"
              @tab="shelf = $event"
              @remove="remove"
              @move="move"
              @review="review"
              @cancel-review="
                reviewing = false;
                confirmed = false;
              "
              @confirm="confirmed = $event"
              @release="releaseSimulation"
              @advance="advanceSimulation"
              @collapse="minimizeShelf"
            />
          </template>
          <template #dock-summary
            >Stage {{ staged.length }} · Execution {{ execution.length }}</template
          >
        </CadenceWorkspaceLayout>
      </div>
    </main>
    <footer class="study-statusbar">
      <span role="status" aria-live="polite">{{
        feedback || "Select spacecraft · browse commands · prepare in place"
      }}</span
      ><span
        >Drafts {{ staged.length }}<span class="study-separator-dot">·</span>Execution
        {{ execution.length }}</span
      >
    </footer>
  </div>
</template>
