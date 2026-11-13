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
}>();
const emit = defineEmits<{
  spacecraft: [id: string];
  range: [selection: TimeSelection];
  refresh: [choice: RefreshChoice];
  edit: [];
  menu: [id: MenuId];
}>();
type MenuId = "versions" | "copy" | "export" | "kiosk";
const menu = computed(() => [
  { id: "versions" as const, label: "Versions" },
  ...(props.canEdit ? [{ id: "copy" as const, label: "Save as copy…" }] : []),
  // ux § Export: the bundle (JSON); the export endpoint needs dashboard authoring.
  ...(props.canEdit ? [{ id: "export" as const, label: "Export" }] : []),
  { id: "kiosk" as const, label: "Kiosk" },
]);
</script>

<template>
  <span class="flex items-center gap-2">
    <ViewerControls
      :scope-options="scopeOptions"
      :spacecraft="spacecraft"
      :selection="selection"
      :refresh="refresh"
      @spacecraft="emit('spacecraft', $event)"
      @range="emit('range', $event)"
      @refresh="emit('refresh', $event)"
    />
    <ApButton v-if="canEdit" variant="secondary" size="compact" @click="emit('edit')"
      >Edit</ApButton
    >
    <MoreMenu :items="menu" @select="emit('menu', $event)" />
  </span>
</template>
