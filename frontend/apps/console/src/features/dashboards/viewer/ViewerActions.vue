<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton } from "@/ui";
import type { TimeSelection } from "../model/time-range.ts";
import MoreMenu from "./MoreMenu.vue";
import RefreshSheet from "./RefreshSheet.vue";
import { refreshWords } from "./refresh-words.ts";
import ViewerControls from "./ViewerControls.vue";
import type { RefreshChoice } from "./useDashboardView.ts";

/**
 * The viewer's header actions: scope, range, refresh, Edit (authors, not on phones) and ⋯. On a
 * phone only ⋯ is here (ux Dashboards.md §Phone): scope and range are the header's second row, and
 * refresh is a ⋯ item opening a sheet.
 */
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
const refreshSheet = ref<InstanceType<typeof RefreshSheet> | null>(null);
const menu = computed(() => [
  ...(props.phone
    ? [{ id: "refresh" as const, label: `Refresh: ${refreshWords(props.refresh)}…` }]
    : []),
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
      v-if="!phone"
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
    <MoreMenu
      :items="menu"
      data-viewer-menu
      @select="(id) => (id === 'refresh' ? refreshSheet?.open() : emit('menu', id))"
    />
    <RefreshSheet
      v-if="phone"
      ref="refreshSheet"
      :refresh="refresh"
      @pick="emit('refresh', $event)"
    />
  </span>
</template>
