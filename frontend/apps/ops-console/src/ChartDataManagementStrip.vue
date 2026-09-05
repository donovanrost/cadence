<script setup lang="ts">
type Attributes = Record<string, string>;

type ComparisonPresentation = {
  class: string;
  attrs: Attributes;
  text: string;
};

type BadgePresentation = {
  key: string;
  tag: "button" | "span";
  class: string;
  attrs: Attributes;
  text: string;
};

type ChartDataManagementStripPresentation = {
  root: {
    class: string;
    attrs: Attributes;
  };
  comparison: ComparisonPresentation | null;
  badges: BadgePresentation[];
};

defineProps<{ presentation: ChartDataManagementStripPresentation }>();
</script>

<template>
  <div :class="presentation.root.class" v-bind="presentation.root.attrs">
    <span
      v-if="presentation.comparison"
      :class="presentation.comparison.class"
      v-bind="presentation.comparison.attrs"
      >{{ presentation.comparison.text }}</span
    >
    <template v-for="badge in presentation.badges" :key="badge.key">
      <button v-if="badge.tag === 'button'" :class="badge.class" v-bind="badge.attrs">
        {{ badge.text }}
      </button>
      <span v-else :class="badge.class" v-bind="badge.attrs">{{ badge.text }}</span>
    </template>
  </div>
</template>
