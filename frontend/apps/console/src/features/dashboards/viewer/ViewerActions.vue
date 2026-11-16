<script setup lang="ts">
import { computed } from "vue";
import { ApButton } from "@/ui";
import type { TimeSelection } from "../model/time-range.ts";
import MoreMenu from "./MoreMenu.vue";
import ViewerControls from "./ViewerControls.vue";
import type { RefreshChoice } from "./useDashboardView.ts";

/** The viewer's header actions: scope, range, refresh, Edit (authors, not on phones) and ⋯. */
const props = defineProps<{
  scopeOptions: readonly { id: string; name: string }[];
  spacecraft: string;
  selection: TimeSelection;
  refresh: RefreshChoice;
  canEdit: boolean;
  /** Phones are view-only (ux): no Settings or Activity and diagnostics entry. */
  phone: boolean;
}>();
const emit = defineEmits<{
  spacecraft: [id: string];
  range: [selection: TimeSelection];
  refresh: [choice: RefreshChoice];
  edit: [];
  menu: [id: MenuId];
}>();
type MenuId = "versions" | "settings" | "activity" | "copy" | "snapshot" | "export" | "kiosk";
const menu = computed(() => [
  { id: "versions" as const, label: "Versions" },
  // ux § Settings: authors get all four tabs; everyone else reads Activity and Diagnostics there.
  ...(props.phone
    ? []
    : props.canEdit
      ? [{ id: "settings" as const, label: "Settings" }]
      : [{ id: "activity" as const, label: "Activity and diagnostics" }]),
  ...(props.canEdit ? [{ id: "copy" as const, label: "Save as copy…" }] : []),
  // ux § Snapshots and § Export; D16 and D19 need dashboard authoring.
  ...(props.canEdit
    ? [
        { id: "snapshot" as const, label: "Take snapshot…" },
        { id: "export" as const, label: "Export" },
      ]
    : []),
  { id: "kiosk" as const, label: "Kiosk" },
]);
</script>

<template>
  <span class="flex flex-wrap items-center gap-2">
    <ViewerControls
      :scope-options="scopeOptions"
      :spacecraft="spacecraft"
      :selection="selection"
      :refresh="refresh"
      @spacecraft="emit('spacecraft', $event)"
      @range="emit('range', $event)"
      @refresh="emit('refresh', $event)"
    />
    <ApButton
      v-if="canEdit"
      variant="secondary"
      size="compact"
      data-edit-dashboard
      @click="emit('edit')"
      >Edit</ApButton
    >
    <MoreMenu :items="menu" data-viewer-menu @select="emit('menu', $event)" />
  </span>
</template>
