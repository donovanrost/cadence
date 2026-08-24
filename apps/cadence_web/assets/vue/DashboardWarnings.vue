<script setup>
import WidgetWarning from "./WidgetWarning.vue"

const props = defineProps({
  presentation: {type: Object, required: true}
})
</script>

<template>
  <div
    :id="props.presentation.root.id"
    :class="props.presentation.root.class"
    v-bind="props.presentation.root.attrs"
  >
    <span :class="props.presentation.label.class">{{ props.presentation.label.text }}</span>
    <span
      v-if="props.presentation.fallback.visible"
      :class="props.presentation.fallback.class"
    >{{ props.presentation.fallback.text }}</span>
    <div
      v-for="warning in props.presentation.warnings"
      :id="warning.component_id"
      :key="warning.component_id"
      class="contents"
    >
      <WidgetWarning :presentation="warning" />
    </div>
  </div>
</template>
