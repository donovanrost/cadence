<script setup lang="ts">
import PublishValidation from "./PublishValidation.vue";
import VersionList from "./VersionList.vue";

type Attributes = Record<string, string>;

type TextPresentation = {
  attrs: Attributes;
  text: string;
};

type RuntimeDefaultRow = {
  key: string;
  order: number;
  label: TextPresentation;
  value: TextPresentation;
};

type RuntimeDefaultContext = {
  key: string;
  order: number;
  attrs: Attributes;
  rows: RuntimeDefaultRow[];
};

type PanelPresentation = {
  version_list: Record<string, unknown>;
  publish_validation: Record<string, unknown> | null;
  publish_impact: null | {
    root: { attrs: Attributes };
    header: {
      attrs: Attributes;
      heading: TextPresentation;
      badge: TextPresentation;
    };
    message: TextPresentation;
  };
  runtime_defaults: null | {
    root: { attrs: Attributes };
    header: {
      attrs: Attributes;
      heading: TextPresentation;
      badge: TextPresentation;
    };
    contexts: {
      attrs: Attributes;
      items: RuntimeDefaultContext[];
    };
  };
};

defineProps<{ presentation: PanelPresentation }>();
</script>

<template>
  <VersionList :presentation="presentation.version_list" />

  <PublishValidation
    v-if="presentation.publish_validation"
    :presentation="presentation.publish_validation"
  />

  <section v-if="presentation.publish_impact" v-bind="presentation.publish_impact.root.attrs">
    <div v-bind="presentation.publish_impact.header.attrs">
      <h3 v-bind="presentation.publish_impact.header.heading.attrs">
        {{ presentation.publish_impact.header.heading.text }}
      </h3>
      <span v-bind="presentation.publish_impact.header.badge.attrs">
        {{ presentation.publish_impact.header.badge.text }}
      </span>
    </div>
    <p v-bind="presentation.publish_impact.message.attrs">
      {{ presentation.publish_impact.message.text }}
    </p>
  </section>

  <section v-if="presentation.runtime_defaults" v-bind="presentation.runtime_defaults.root.attrs">
    <div v-bind="presentation.runtime_defaults.header.attrs">
      <h3 v-bind="presentation.runtime_defaults.header.heading.attrs">
        {{ presentation.runtime_defaults.header.heading.text }}
      </h3>
      <span v-bind="presentation.runtime_defaults.header.badge.attrs">
        {{ presentation.runtime_defaults.header.badge.text }}
      </span>
    </div>
    <div v-bind="presentation.runtime_defaults.contexts.attrs">
      <dl
        v-for="context in presentation.runtime_defaults.contexts.items"
        :key="context.key"
        v-bind="context.attrs"
      >
        <template v-for="row in context.rows" :key="row.key">
          <dt v-bind="row.label.attrs">{{ row.label.text }}</dt>
          <dd v-bind="row.value.attrs">{{ row.value.text }}</dd>
        </template>
      </dl>
    </div>
  </section>
</template>
