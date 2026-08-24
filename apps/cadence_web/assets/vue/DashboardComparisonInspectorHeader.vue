<script setup lang="ts">
type Attributes = Record<string, string>

type IconPresentation = {
  name: string
  class: string
  text: string
}

type ElementPresentation = {
  tag: string
  class: string
  attrs: Attributes
}

type TextPresentation = ElementPresentation & {
  text: string
}

type DashboardComparisonInspectorHeaderPresentation = {
  root: ElementPresentation
  leading: ElementPresentation & {icon: IconPresentation}
  copy: ElementPresentation & {
    title: TextPresentation
    subtitle: TextPresentation
  }
  close: ElementPresentation & {icon: IconPresentation}
}

defineProps<{presentation: DashboardComparisonInspectorHeaderPresentation}>()
</script>

<template>
  <component
    :is="presentation.root.tag"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <component
      :is="presentation.leading.tag"
      :class="presentation.leading.class"
      v-bind="presentation.leading.attrs"
    >
      <span :class="[presentation.leading.icon.name, presentation.leading.icon.class]">{{
        presentation.leading.icon.text
      }}</span>
    </component>
    <component
      :is="presentation.copy.tag"
      :class="presentation.copy.class"
      v-bind="presentation.copy.attrs"
    >
      <component
        :is="presentation.copy.title.tag"
        :class="presentation.copy.title.class"
        v-bind="presentation.copy.title.attrs"
      >{{ presentation.copy.title.text }}</component>
      <component
        :is="presentation.copy.subtitle.tag"
        :class="presentation.copy.subtitle.class"
        v-bind="presentation.copy.subtitle.attrs"
      >{{ presentation.copy.subtitle.text }}</component>
    </component>
    <component
      :is="presentation.close.tag"
      :class="presentation.close.class"
      v-bind="presentation.close.attrs"
    >
      <span :class="[presentation.close.icon.name, presentation.close.icon.class]">{{
        presentation.close.icon.text
      }}</span>
    </component>
  </component>
</template>
