<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import CadenceSplitterGroup from "./CadenceSplitterGroup.vue";
import CadenceSplitterPanel from "./CadenceSplitterPanel.vue";
import CadenceSplitterResizeHandle from "./CadenceSplitterResizeHandle.vue";
import { useWorkspaceDock, workspaceDockDefaultSize } from "./useWorkspaceDock";

const props = withDefaults(
  defineProps<{
    id: string;
    storageId: string;
    inspector?: boolean;
    dock?: boolean;
    primaryResizeLabel?: string;
    inspectorResizeLabel?: string;
    dockResizeLabel?: string;
    dockTitle?: string;
    dockIcon?: string;
    dockExpandLabel?: string;
  }>(),
  {
    inspector: false,
    dock: false,
    primaryResizeLabel: "Resize navigation and browser",
    inspectorResizeLabel: "Resize browser and inspector",
    dockResizeLabel: "Resize workspace and dock",
    dockTitle: "Activity",
    dockIcon: "hero-queue-list",
    dockExpandLabel: "Expand dock",
  },
);
const emit = defineEmits<{ "update:dock": [expanded: boolean] }>();
const dockContent = ref<HTMLElement>();
const dockToggle = ref<HTMLButtonElement>();
const dockPanel = ref<InstanceType<typeof CadenceSplitterPanel>>();
let focusExpandedDock = false;
let focusMinimizedDock = false;
function minimizeDock() {
  focusMinimizedDock = true;
  emit("update:dock", false);
}
const dockGesture = useWorkspaceDock(dockPanel, () => props.dock, minimizeDock);
const { dragging: draggingDock, snapReady } = dockGesture;
function expandDock() {
  focusExpandedDock = true;
  emit("update:dock", true);
}
watch(
  () => props.dock,
  async (expanded) => {
    const restoreFocus =
      !expanded && (focusMinimizedDock || dockContent.value?.contains(document.activeElement));
    await nextTick();
    if (restoreFocus) dockToggle.value?.focus({ preventScroll: true });
    if (expanded && focusExpandedDock) dockContent.value?.focus({ preventScroll: !compact.value });
    focusExpandedDock = false;
    focusMinimizedDock = false;
  },
);
const compact = ref(false);
watch(compact, () => dockGesture.cancelDrag());
let media: MediaQueryList | undefined;
function updateCompact() {
  compact.value = media?.matches ?? false;
}
onMounted(() => {
  media = window.matchMedia("(max-width: 900px)");
  updateCompact();
  media.addEventListener("change", updateCompact);
});
onBeforeUnmount(() => media?.removeEventListener("change", updateCompact));
</script>

<template>
  <div class="cadence-workspace-layout" :class="{ 'is-compact': compact }">
    <div v-if="$slots.toolbar" class="cadence-workspace-layout__toolbar">
      <slot name="toolbar" />
    </div>
    <div class="cadence-workspace-layout__body">
      <CadenceSplitterGroup
        :id="`${id}-vertical`"
        direction="vertical"
        :auto-save-id="`${storageId}-height`"
      >
        <CadenceSplitterPanel :id="`${id}-work-area`" :order="1" :default-size="66" :min-size="40">
          <CadenceSplitterGroup
            :id="`${id}-horizontal`"
            :direction="compact ? 'vertical' : 'horizontal'"
            :auto-save-id="`${storageId}-${compact ? 'mobile' : 'width'}`"
          >
            <CadenceSplitterPanel :id="`${id}-primary`" :order="1" :default-size="30" :min-size="22"
              ><slot name="primary"
            /></CadenceSplitterPanel>
            <CadenceSplitterResizeHandle :id="`${id}-primary-resize`" :label="primaryResizeLabel" />
            <CadenceSplitterPanel
              :id="`${id}-secondary`"
              :order="2"
              :default-size="34"
              :min-size="23"
              ><slot name="secondary"
            /></CadenceSplitterPanel>
            <template v-if="inspector">
              <CadenceSplitterResizeHandle
                :id="`${id}-inspector-resize`"
                :label="inspectorResizeLabel"
              />
              <CadenceSplitterPanel
                :id="`${id}-inspector`"
                :order="3"
                :default-size="36"
                :min-size="26"
                ><slot name="inspector"
              /></CadenceSplitterPanel>
            </template>
          </CadenceSplitterGroup>
        </CadenceSplitterPanel>
        <!-- Keep the dock registered and mounted to preserve its size and local edits. -->
        <template v-if="$slots.dock">
          <CadenceSplitterResizeHandle
            v-show="dock"
            :id="`${id}-dock-resize`"
            :label="dockResizeLabel"
            @dragging="dockGesture.onDragging"
          />
          <CadenceSplitterPanel
            v-show="dock"
            :id="`${id}-dock`"
            ref="dockPanel"
            class="cadence-workspace-layout__dock"
            :class="{ 'is-minimizing': draggingDock && snapReady }"
            :order="2"
            :default-size="workspaceDockDefaultSize"
            :min-size="0"
            :max-size="60"
            @resize="dockGesture.onResize"
          >
            <div
              ref="dockContent"
              class="cadence-workspace-layout__dock-content"
              role="group"
              :aria-label="dockTitle"
              tabindex="-1"
            >
              <slot name="dock" />
            </div>
          </CadenceSplitterPanel>
        </template>
      </CadenceSplitterGroup>
    </div>
    <button
      v-if="$slots.dock && !dock"
      :id="`${id}-dock-expand`"
      ref="dockToggle"
      type="button"
      class="cadence-workspace-layout__dock-toggle"
      :aria-label="dockExpandLabel"
      :aria-controls="`${id}-dock`"
      :aria-expanded="false"
      :aria-describedby="$slots['dock-summary'] ? `${id}-dock-summary` : undefined"
      @click="expandDock"
    >
      <span :class="dockIcon" class="cadence-workspace-layout__dock-icon" aria-hidden="true" />
      <strong>{{ dockTitle }}</strong>
      <span
        v-if="$slots['dock-summary']"
        :id="`${id}-dock-summary`"
        class="cadence-workspace-layout__dock-summary"
        ><slot name="dock-summary"
      /></span>
      <span class="hero-chevron-up cadence-workspace-layout__dock-icon" aria-hidden="true" />
    </button>
    <div v-if="$slots.status" class="cadence-workspace-layout__status"><slot name="status" /></div>
  </div>
</template>

<style scoped>
.cadence-workspace-layout {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
  height: 100%;
  overflow: hidden;
  color: var(--text-bright);
  background: var(--surface-base);
}
.cadence-workspace-layout__toolbar,
.cadence-workspace-layout__status {
  display: flex;
  flex: none;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px 16px;
  padding: 9px 14px;
  background: var(--surface-raised);
}
.cadence-workspace-layout__dock-content {
  height: 100%;
  min-height: 0;
}
.cadence-workspace-layout__dock-toggle {
  position: sticky;
  bottom: 0;
  z-index: 1;
  display: flex;
  flex: none;
  align-items: center;
  gap: 10px;
  min-height: calc(8 * var(--workspace-space, 4px) + 8px);
  margin: 0 6px 6px;
  padding: calc(2 * var(--workspace-space, 4px)) calc(3 * var(--workspace-space, 4px));
  border: 1px solid var(--border-subtle);
  border-radius: 3px;
  background: var(--surface-raised);
  color: var(--text-bright);
  font: 12px var(--font-sans);
  text-align: left;
  cursor: pointer;
}
.cadence-workspace-layout__dock-toggle:hover {
  background: var(--surface-elevated);
  border-color: var(--border-strong);
}
.cadence-workspace-layout__dock-toggle:focus-visible {
  outline: 2px solid var(--color-action);
  outline-offset: -2px;
}
.cadence-workspace-layout__dock-toggle strong {
  min-width: 0;
  overflow-wrap: anywhere;
  font-weight: 650;
}
.cadence-workspace-layout__dock-icon {
  flex: none;
  width: 16px;
  height: 16px;
  color: var(--text-subtle);
}
.cadence-workspace-layout__dock-icon:last-child {
  margin-left: auto;
}
.cadence-workspace-layout__dock-summary {
  color: var(--text-subtle);
  font: 10px var(--font-mono);
}
.cadence-workspace-layout__toolbar {
  border-bottom: 1px solid var(--border-default);
}
.cadence-workspace-layout__body {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  padding: 6px;
}
.cadence-workspace-layout__dock.is-minimizing {
  --pane-header-background: color-mix(in srgb, var(--red-500) 22%, var(--surface-raised));
}
.cadence-workspace-layout__status {
  border-top: 1px solid var(--border-subtle);
  padding-block: 5px;
  color: var(--text-subtle);
  font-size: 11px;
}
.cadence-workspace-layout.is-compact {
  overflow: auto;
}
.is-compact .cadence-workspace-layout__body {
  min-height: 1450px;
  flex-shrink: 0;
}
</style>
