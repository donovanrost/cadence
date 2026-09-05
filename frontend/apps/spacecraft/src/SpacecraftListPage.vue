<script setup lang="ts">
import SpacecraftList from "./SpacecraftList.vue";

type Attrs = Record<string, string>;

type ElementPresentation = {
  attrs: Attrs;
};

type TextPresentation = ElementPresentation & {
  text: string;
};

type BreadcrumbItem = {
  key: string;
  separator: TextPresentation | null;
  link: TextPresentation | null;
  current: TextPresentation | null;
};

type SpacecraftListProps = InstanceType<typeof SpacecraftList>["$props"];

type Presentation = {
  root: ElementPresentation;
  header: {
    attrs: Attrs;
    body: ElementPresentation;
    content: ElementPresentation;
    title: TextPresentation;
    subtitle: TextPresentation;
  };
  breadcrumbs: {
    attrs: Attrs;
    items: BreadcrumbItem[];
  };
  summary_tiles: SpacecraftListProps["summary_tiles"];
  roster: SpacecraftListProps["roster"];
  profiles: SpacecraftListProps["profiles"];
};

const props = defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <header v-bind="props.presentation.header.attrs">
      <div v-bind="props.presentation.header.body.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <nav v-bind="props.presentation.breadcrumbs.attrs">
            <template v-for="item in props.presentation.breadcrumbs.items" :key="item.key">
              <span v-if="item.separator" v-bind="item.separator.attrs">
                {{ item.separator.text }}
              </span>
              <a v-if="item.link" v-bind="item.link.attrs">{{ item.link.text }}</a>
              <span v-if="item.current" v-bind="item.current.attrs">
                {{ item.current.text }}
              </span>
            </template>
          </nav>
          <h1 v-bind="props.presentation.header.title.attrs">
            {{ props.presentation.header.title.text }}
          </h1>
          <p v-bind="props.presentation.header.subtitle.attrs">
            {{ props.presentation.header.subtitle.text }}
          </p>
        </div>
      </div>
    </header>

    <SpacecraftList
      :summary_tiles="props.presentation.summary_tiles"
      :roster="props.presentation.roster"
      :profiles="props.presentation.profiles"
    />
  </div>
</template>
