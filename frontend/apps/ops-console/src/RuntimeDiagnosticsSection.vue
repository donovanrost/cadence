<script setup lang="ts">
type Attributes = Record<string, string>;

type ElementPresentation = {
  tag: string;
  class: string;
  attrs: Attributes;
  body: string;
};

type Presentation = {
  root: Omit<ElementPresentation, "body">;
  title: ElementPresentation;
  rows: Omit<ElementPresentation, "body"> & {
    items: Array<{
      key: number;
      label: ElementPresentation;
      value: ElementPresentation;
    }>;
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <component
    :is="presentation.root.tag"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <component
      :is="presentation.title.tag"
      :class="presentation.title.class"
      v-bind="presentation.title.attrs"
    >
      {{ presentation.title.body }}
    </component>
    <component
      :is="presentation.rows.tag"
      :class="presentation.rows.class"
      v-bind="presentation.rows.attrs"
    >
      <template v-for="row in presentation.rows.items" :key="row.key">
        <component :is="row.label.tag" :class="row.label.class" v-bind="row.label.attrs">
          {{ row.label.body }}
        </component>
        <component :is="row.value.tag" :class="row.value.class" v-bind="row.value.attrs">
          {{ row.value.body }}
        </component>
      </template>
    </component>
  </component>
</template>
