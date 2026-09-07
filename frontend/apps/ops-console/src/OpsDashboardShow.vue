<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import DashboardCanvas from "./DashboardCanvas.vue";
import DashboardEditorGuard from "./DashboardEditorGuard.vue";

const emit = defineEmits(["layout_changed"]);

defineProps<{
  page: {
    id: string;
    dashboard_id: string;
    mode: "view" | "edit";
    header: { eyebrow: string; heading: string; copy: string };
  };
  canvas: Record<string, unknown>;
  editor_guard: { editor_dirty: boolean };
}>();
</script>

<template>
  <main :id="page.id" class="min-h-0 flex-1 overflow-y-auto">
    <CadencePageHeading>
      <template #title>{{ page.header.heading }}</template>
      <template #eyebrow>{{ page.header.eyebrow }}</template>
      <template #description>{{ page.header.copy }}</template>
    </CadencePageHeading>
    <DashboardEditorGuard v-if="page.mode === 'edit'" :editor_dirty="editor_guard.editor_dirty" />
    <DashboardCanvas :presentation="canvas" @layout_changed="emit('layout_changed', $event)" />
  </main>
</template>
