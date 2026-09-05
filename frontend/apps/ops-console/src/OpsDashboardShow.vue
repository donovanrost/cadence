<script setup lang="ts">
import DashboardCanvas from "./DashboardCanvas.vue";
import DashboardEditorGuard from "./DashboardEditorGuard.vue";

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
    <header class="border-b border-primary/20 px-5 py-6">
      <div class="mx-auto max-w-[100rem]">
        <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70">
          {{ page.header.eyebrow }}
        </p>
        <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.heading }}</h1>
        <p class="mt-2 text-sm text-base-content/60">{{ page.header.copy }}</p>
      </div>
    </header>
    <DashboardEditorGuard
      v-if="page.mode === 'edit'"
      :editor_dirty="editor_guard.editor_dirty"
    />
    <DashboardCanvas :presentation="canvas" />
  </main>
</template>
