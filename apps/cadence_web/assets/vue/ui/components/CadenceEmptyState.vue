<script setup lang="ts">
import type {EmptyStatePresentation} from "./page_shell"

const props = defineProps<{emptyState: EmptyStatePresentation}>()
</script>

<template>
  <div v-bind="props.emptyState.attrs">
    <p v-bind="props.emptyState.title.attrs">
      {{ props.emptyState.title.text }}
    </p>
    <p v-bind="props.emptyState.description.attrs">
      {{ props.emptyState.description.text }}
    </p>
    <div v-bind="props.emptyState.action_container.attrs">
      <a v-bind="props.emptyState.action.attrs">
        <span v-bind="props.emptyState.action.icon.attrs"></span>
        {{ props.emptyState.action.text }}
      </a>
    </div>
  </div>
</template>
