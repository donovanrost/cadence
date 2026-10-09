<script setup lang="ts">
import { computed } from "vue";
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import DashboardMoreMenu from "./DashboardMoreMenu.vue";
import SaveMenu from "./SaveMenu.vue";

/**
 * The dashboard's identity bar. Its route opts out of the host page heading,
 * so this owns the page's single h1 and keeps the canvas full height.
 * Like Grafana: Edit in view mode; Exit edit and Save dashboard while editing.
 */
const props = defineProps<{
  name: string;
  description: string | null;
  author: boolean;
  editing: boolean;
  dirty: boolean;
  conflict: boolean;
  pending: boolean;
  base: string;
  diagnosticsHref: string | null;
}>();
const emit = defineEmits<{ edit: []; exit: []; save: []; copy: []; versions: [] }>();
defineSlots<{ default(): unknown }>();
const directory = computed(() => props.base.replace(/\/[^/]+$/, ""));
</script>

<template>
  <header class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-base-300/60 pb-2">
    <div class="flex min-w-0 items-center gap-2">
      <a
        :href="directory"
        class="cadence-icon-button"
        aria-label="All dashboards"
        title="All dashboards"
      >
        <CadenceIcon name="hero-squares-2x2" />
      </a>
      <h1 class="cd-page-title truncate" :title="description ?? undefined">{{ name }}</h1>
      <CadenceBadge v-if="editing" tone="info">Editing</CadenceBadge>
    </div>
    <div class="flex min-w-0 flex-1 items-center">
      <slot />
    </div>
    <div class="ml-auto flex shrink-0 items-center gap-2">
      <template v-if="editing">
        <CadenceButton variant="quiet" size="sm" :disabled="pending" @click="emit('exit')">
          Exit edit
        </CadenceButton>
        <SaveMenu
          :dirty="dirty"
          :disabled="pending || conflict"
          @save="emit('save')"
          @copy="emit('copy')"
          @versions="emit('versions')"
        />
      </template>
      <template v-else>
        <CadenceButton v-if="author" variant="primary" size="sm" @click="emit('edit')">
          <CadenceIcon name="hero-pencil-square" />Edit
        </CadenceButton>
        <DashboardMoreMenu
          :base="base"
          :author="author"
          :diagnostics-href="diagnosticsHref"
          @versions="emit('versions')"
        />
      </template>
    </div>
  </header>
</template>
