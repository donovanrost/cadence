<script setup lang="ts">
type Attributes = Record<string, string>

type ChildPresentation = {
  key: string
  tag: string
  attrs: Attributes
  text: string
}

type ElementPresentation = ChildPresentation & {
  children: ChildPresentation[]
}

type DashboardEditorActionsPresentation = {
  elements: ElementPresentation[]
}

defineProps<{presentation: DashboardEditorActionsPresentation}>()
</script>

<template>
  <component
    :is="element.tag"
    v-for="element in presentation.elements"
    :key="element.key"
    v-bind="element.attrs"
  >
    <component
      :is="child.tag"
      v-for="child in element.children"
      :key="child.key"
      v-bind="child.attrs"
    >{{ child.text }}</component>
    {{ element.text }}
  </component>
</template>
