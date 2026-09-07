<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { presentationBreadcrumbs } from "@cadence/ui/page-chrome";
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
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading :breadcrumbs="presentationBreadcrumbs(props.presentation.breadcrumbs)">
      <template #title>{{ props.presentation.header.title.text }}</template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
    </CadencePageHeading>

    <SpacecraftList
      :summary_tiles="props.presentation.summary_tiles"
      :roster="props.presentation.roster"
      :profiles="props.presentation.profiles"
    />
  </div>
</template>
