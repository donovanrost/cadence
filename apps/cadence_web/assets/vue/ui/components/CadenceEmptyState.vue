<script setup lang="ts">
import CadenceEmptyStateFrame from "./CadenceEmptyStateFrame.vue"
import type {EmptyStatePresentation} from "./page_shell"

const props = defineProps<{emptyState: EmptyStatePresentation}>()
</script>

<template>
  <CadenceEmptyStateFrame
    :root-attrs="props.emptyState.attrs"
    :title-attrs="props.emptyState.title.attrs"
    :description-attrs="props.emptyState.description.attrs"
    :action-container-attrs="props.emptyState.action_container.attrs"
  >
    <template #title>
      {{ props.emptyState.title.text }}
    </template>
    <template #description>
      {{ props.emptyState.description.text }}
    </template>
    <template #action>
      <a v-bind="props.emptyState.action.attrs">
        <span v-bind="props.emptyState.action.icon.attrs"></span>
        {{ props.emptyState.action.text }}
      </a>
    </template>
  </CadenceEmptyStateFrame>
</template>
