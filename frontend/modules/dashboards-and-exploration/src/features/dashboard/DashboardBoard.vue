<script setup lang="ts">
import { computed, reactive } from "vue";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../workspace/contracts";
import { workspaceDomId } from "../workspace/snapshot-presentation";
import type { LayoutEdit } from "./contracts";
import BoardGridView from "./BoardGridView.vue";
import BoardSectionHeader from "./BoardSectionHeader.vue";
import WidgetPanel from "./WidgetPanel.vue";

const props = defineProps<{
  snapshot: WorkspaceSnapshot;
  editing: boolean;
  live: boolean;
  now: number;
  staleAfterMs: number;
  instance: string;
}>();
const emit = defineEmits<{
  layout: [layouts: LayoutEdit[]];
  inspect: [placement: WorkspacePlacement];
  configure: [authoredId: string];
  remove: [authoredId: string];
  editSection: [sectionId: string];
  moveSection: [sectionId: string, direction: "up" | "down"];
  removeSection: [sectionId: string];
}>();

const rootId = computed(() =>
  workspaceDomId(
    props.instance,
    props.snapshot.organization_id,
    props.snapshot.mission_id,
    props.snapshot.dashboard_id,
  ),
);
const groups = computed(() => {
  const sections = props.snapshot.sections.map((section, index) => ({
    key: section.id,
    section,
    first: index === 0,
    last: index === props.snapshot.sections.length - 1,
    placements: props.snapshot.placements.filter((p) => p.section_id === section.id),
  }));
  const loose = props.snapshot.placements.filter((p) => p.section_id === null);
  return loose.length || !sections.length
    ? [{ key: "", section: null, first: true, last: true, placements: loose }, ...sections]
    : sections;
});
// Disclosure state belongs to this browser; live refreshes must not reopen sections.
const open = reactive(new Map<string, boolean>());
const isOpen = (key: string, collapsed: boolean) => open.get(key) ?? !collapsed;
const toggle = (key: string, collapsed: boolean) => open.set(key, !isOpen(key, collapsed));
</script>

<template>
  <div :id="rootId" class="space-y-3" :data-workspace-snapshot="snapshot.dashboard_id">
    <section
      v-for="group in groups"
      :key="group.key"
      :aria-label="group.section?.title ?? 'Dashboard widgets'"
    >
      <BoardSectionHeader
        v-if="group.section"
        :section="group.section"
        :count="group.placements.length"
        :open="isOpen(group.key, group.section.collapsed)"
        :editing="editing"
        :first="group.first"
        :last="group.last"
        @toggle="toggle(group.key, group.section.collapsed)"
        @edit="emit('editSection', group.key)"
        @move="(direction) => emit('moveSection', group.key, direction)"
        @remove="emit('removeSection', group.key)"
      />
      <div v-show="!group.section || isOpen(group.key, group.section.collapsed)">
        <BoardGridView
          :placements="group.placements"
          :geometry="snapshot.grid"
          :editing="editing"
          :open="!group.section || isOpen(group.key, group.section.collapsed)"
          @layout="(layouts) => emit('layout', layouts)"
        >
          <template #default="{ placement }">
            <WidgetPanel
              :placement="placement"
              :context="snapshot.context"
              :editing="editing"
              :live="live"
              :now="now"
              :stale-after-ms="staleAfterMs"
              :dom-id="workspaceDomId(rootId, 'placement', placement.id)"
              :group="rootId"
              @inspect="emit('inspect', placement)"
              @configure="emit('configure', placement.authored_id)"
              @remove="emit('remove', placement.authored_id)"
            />
          </template>
        </BoardGridView>
        <p
          v-if="group.section && !group.placements.length"
          class="rounded-sm border border-dashed border-base-300 px-4 py-6 text-center text-xs text-base-content/60"
        >
          No widgets in this section{{ editing ? " yet. Add one from the toolbar." : "." }}
        </p>
      </div>
    </section>
  </div>
</template>
