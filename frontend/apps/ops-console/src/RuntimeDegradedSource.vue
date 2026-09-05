<script setup lang="ts">
type DataAttrs = Record<string, string | null>;

type TextPresentation = {
  text: string;
  class: string;
};

type IconPresentation = {
  name: string;
  class: string;
};

type RootPresentation = {
  id: string | null;
  class: string;
  attrs: DataAttrs;
};

type SummaryField = {
  key: string;
  label: TextPresentation;
  value: TextPresentation & { attrs: DataAttrs };
};

type SummaryPresentation = {
  kind: "summary";
  root: RootPresentation;
  heading: TextPresentation;
  headline: TextPresentation;
  fields_class: string;
  fields: SummaryField[];
};

type CollectionField = TextPresentation & {
  key: string;
  attrs: DataAttrs;
};

type CollectionItem = {
  key: string;
  type: "button";
  class: string;
  attrs: DataAttrs;
  evidence_attrs: DataAttrs;
  render_attrs: DataAttrs;
  primary: {
    class: string;
    icon: IconPresentation;
    text: TextPresentation;
  };
  fields: CollectionField[];
};

type CollectionPresentation = {
  kind: "drilldowns" | "capability_postures" | "dependency_causes";
  root: RootPresentation;
  heading: TextPresentation;
  items_container: {
    id: string | null;
    class: string;
  };
  items: CollectionItem[];
};

defineProps<{ presentation: SummaryPresentation | CollectionPresentation }>();
</script>

<template>
  <section
    v-if="presentation.kind === 'summary'"
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <h3 :class="presentation.heading.class">{{ presentation.heading.text }}</h3>
    <p :class="presentation.headline.class">{{ presentation.headline.text }}</p>
    <dl :class="presentation.fields_class">
      <template v-for="field in presentation.fields" :key="field.key">
        <dt :class="field.label.class">{{ field.label.text }}</dt>
        <dd :class="field.value.class" v-bind="field.value.attrs">{{ field.value.text }}</dd>
      </template>
    </dl>
  </section>

  <section
    v-else
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <h3 :class="presentation.heading.class">{{ presentation.heading.text }}</h3>
    <div :id="presentation.items_container.id" :class="presentation.items_container.class">
      <button
        v-for="item in presentation.items"
        :key="item.key"
        :type="item.type"
        :class="item.class"
        v-bind="item.render_attrs"
      >
        <span :class="item.primary.class">
          <span :class="[item.primary.icon.name, item.primary.icon.class]"></span>
          <span :class="item.primary.text.class">{{ item.primary.text.text }}</span>
        </span>
        <span
          v-for="field in item.fields"
          :key="field.key"
          :class="field.class"
          v-bind="field.attrs"
          >{{ field.text }}</span
        >
      </button>
    </div>
  </section>
</template>
