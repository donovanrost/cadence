<script setup lang="ts">
import { computed } from "vue";
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import type { Publication } from "./contracts";
import DashboardMoreMenu from "./DashboardMoreMenu.vue";

/**
 * The dashboard's identity bar. Its route opts out of the host page heading,
 * so this owns the page's single h1 and keeps the canvas full height.
 */
const props = defineProps<{
  name: string;
  description: string | null;
  publication: Publication;
  author: boolean;
  editing: boolean;
  dirty: boolean;
  conflict: boolean;
  pending: boolean;
  base: string;
  diagnosticsHref: string | null;
}>();
const emit = defineEmits<{ edit: []; done: []; save: []; discard: []; publish: [] }>();
defineSlots<{ default(): unknown }>();
const directory = computed(() => props.base.replace(/\/[^/]+$/, ""));
const publishable = computed(
  () => props.author && !props.editing && props.publication.state !== "published",
);
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
      <CadenceBadge v-else-if="publication.state === 'unpublished'" tone="warning">
        Unpublished · v{{ publication.latest_version }}
      </CadenceBadge>
      <CadenceBadge v-else-if="publication.state === 'draft_ahead' && author" tone="warning">
        Draft v{{ publication.latest_version }} · live v{{ publication.published_version }}
      </CadenceBadge>
    </div>
    <div class="flex min-w-0 flex-1 items-center">
      <slot />
    </div>
    <div class="ml-auto flex shrink-0 items-center gap-2">
      <template v-if="editing">
        <CadenceButton
          v-if="dirty || conflict"
          variant="quiet"
          size="sm"
          :disabled="pending"
          @click="emit('discard')"
        >
          {{ conflict ? "Discard & load latest" : "Discard" }}
        </CadenceButton>
        <CadenceButton
          v-if="dirty"
          variant="outline"
          size="sm"
          :loading="pending"
          :disabled="conflict"
          @click="emit('save')"
        >
          Save draft
        </CadenceButton>
        <CadenceButton
          variant="primary"
          size="sm"
          :disabled="pending || conflict"
          @click="emit('done')"
        >
          <CadenceIcon name="hero-check" />{{ dirty ? "Save & exit" : "Done" }}
        </CadenceButton>
      </template>
      <template v-else>
        <CadenceButton
          v-if="publishable"
          variant="outline"
          size="sm"
          :loading="pending"
          @click="emit('publish')"
        >
          <CadenceIcon name="hero-arrow-up-on-square" />Publish v{{ publication.latest_version }}
        </CadenceButton>
        <CadenceButton v-if="author" variant="primary" size="sm" @click="emit('edit')">
          <CadenceIcon name="hero-pencil-square" />Edit
        </CadenceButton>
        <DashboardMoreMenu :base="base" :author="author" :diagnostics-href="diagnosticsHref" />
      </template>
    </div>
  </header>
</template>
