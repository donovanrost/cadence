<script setup lang="ts">
type EditorConflictPresentation = {
  root: { attrs: Record<string, string> };
  icon: { attrs: Record<string, string> };
  message: { class: string; text: string };
  reload: { attrs: Record<string, string>; text: string };
};

const props = defineProps<{ presentation: EditorConflictPresentation }>();
const emit = defineEmits(["reload_editor"]);
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <span v-bind="props.presentation.icon.attrs"></span>
    <p :class="props.presentation.message.class">{{ props.presentation.message.text }}</p>
    <button v-bind="props.presentation.reload.attrs" @click="emit('reload_editor')">
      {{ props.presentation.reload.text }}
    </button>
  </div>
</template>
