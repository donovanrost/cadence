<script setup lang="ts">
type Attributes = Record<string, string>;

type ElementPresentation = {
  key: string;
  tag: string;
  class: string;
  attrs: Attributes;
  text: string;
};

type DashboardComparisonTogglePresentation = {
  root: {
    tag: string;
    class: string;
    attrs: Attributes;
  };
  children: ElementPresentation[];
};

defineProps<{ presentation: DashboardComparisonTogglePresentation }>();
</script>

<template>
  <component
    :is="presentation.root.tag"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <component
      :is="child.tag"
      v-for="child in presentation.children"
      :key="child.key"
      :class="child.class"
      v-bind="child.attrs"
      >{{ child.text }}</component
    >
  </component>
</template>
