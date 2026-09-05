<script setup lang="ts">
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
  <div v-bind="props.presentation.root.attrs">
    <header v-bind="props.presentation.header.attrs">
      <div v-bind="props.presentation.header.body.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <nav v-bind="props.presentation.header.breadcrumbs.attrs">
            <a v-bind="props.presentation.header.breadcrumbs.mission.attrs">
              {{ props.presentation.header.breadcrumbs.mission.text }}
            </a>
            <span v-bind="props.presentation.header.breadcrumbs.separator.attrs">
              {{ props.presentation.header.breadcrumbs.separator.text }}
            </span>
            <span v-bind="props.presentation.header.breadcrumbs.current.attrs">
              {{ props.presentation.header.breadcrumbs.current.text }}
            </span>
          </nav>

          <h1 v-bind="props.presentation.header.title.attrs">
            {{ props.presentation.header.title.text }}
          </h1>
          <p v-bind="props.presentation.header.subtitle.attrs">
            {{ props.presentation.header.subtitle.text }}
          </p>
        </div>
        <div v-bind="props.presentation.header.actions.attrs">
          <a v-bind="props.presentation.header.new_database.attrs">
            <span v-bind="props.presentation.header.new_database.icon.attrs"></span>
            {{ props.presentation.header.new_database.text }}
          </a>
        </div>
      </div>
    </header>

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
