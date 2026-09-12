<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CatalogDatabaseTable from "./CatalogDatabaseTable.vue";

type Attrs = Record<string, string>;

type ElementPresentation = {
  attrs: Attrs;
};

type TextPresentation = ElementPresentation & {
  text: string;
};

type CatalogDatabaseTableProps = InstanceType<typeof CatalogDatabaseTable>["$props"];

type Presentation = {
  root: ElementPresentation;
  header: {
    attrs: Attrs;
    body: ElementPresentation;
    content: ElementPresentation;
    breadcrumbs: {
      attrs: Attrs;
      mission: TextPresentation;
      separator: TextPresentation;
      current: TextPresentation;
    };
    title: TextPresentation;
    subtitle: TextPresentation;
    actions: ElementPresentation;
    new_database: TextPresentation & {
      icon: ElementPresentation;
    };
  };
  empty_state: {
    visible: boolean;
    list: ElementPresentation;
    root: ElementPresentation;
    title: TextPresentation;
    description: TextPresentation;
  };
  card: {
    visible: boolean;
    root: ElementPresentation;
    body: ElementPresentation;
    child_wrapper: ElementPresentation;
    rows: CatalogDatabaseTableProps["rows"];
  };
};

const props = defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading
      :breadcrumbs="[
        {
          label: props.presentation.header.breadcrumbs.mission.text,
          ...(props.presentation.header.breadcrumbs.mission.attrs.href === undefined
            ? {}
            : { href: props.presentation.header.breadcrumbs.mission.attrs.href }),
        },
        { label: props.presentation.header.breadcrumbs.current.text },
      ]"
    >
      <template #title>{{ props.presentation.header.title.text }}</template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
      <template #actions
        ><a v-bind="props.presentation.header.new_database.attrs">
          <span v-bind="props.presentation.header.new_database.icon.attrs"></span>
          {{ props.presentation.header.new_database.text }}
        </a></template
      >
    </CadencePageHeading>

    <div
      v-if="props.presentation.empty_state.visible"
      v-bind="props.presentation.empty_state.list.attrs"
    >
      <div v-bind="props.presentation.empty_state.root.attrs">
        <p v-bind="props.presentation.empty_state.title.attrs">
          {{ props.presentation.empty_state.title.text }}
        </p>
        <p v-bind="props.presentation.empty_state.description.attrs">
          {{ props.presentation.empty_state.description.text }}
        </p>
      </div>
    </div>

    <section
      v-else-if="props.presentation.card.visible"
      v-bind="props.presentation.card.root.attrs"
    >
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.child_wrapper.attrs">
          <CatalogDatabaseTable :rows="props.presentation.card.rows" />
        </div>
      </div>
    </section>
  </div>
</template>
