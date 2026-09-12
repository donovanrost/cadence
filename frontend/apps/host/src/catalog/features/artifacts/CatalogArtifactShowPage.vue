<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { presentationBreadcrumbs } from "@cadence/ui/page-chrome";
import CatalogArtifactShow from "./CatalogArtifactShow.vue";

type Attrs = Record<string, string>;

type ElementPresentation = {
  attrs: Attrs;
};

type TextPresentation = ElementPresentation & {
  text: string;
};

type CatalogArtifactShowProps = InstanceType<typeof CatalogArtifactShow>["$props"];

type BreadcrumbItem = {
  key: string;
  separator: TextPresentation | null;
  link: TextPresentation | null;
  current: TextPresentation | null;
};

type Presentation = {
  root: ElementPresentation;
  header: {
    attrs: Attrs;
    body: ElementPresentation;
    content: ElementPresentation;
    breadcrumbs: {
      attrs: Attrs;
      items: BreadcrumbItem[];
    };
    title: TextPresentation;
  };
  child_wrapper: ElementPresentation;
  artifact_show: {
    artifact: CatalogArtifactShowProps["artifact"];
    runs: CatalogArtifactShowProps["runs"];
  };
};

const props = defineProps<{ presentation: Presentation }>();

const emit = defineEmits<{
  reimport: [];
}>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading
      :breadcrumbs="presentationBreadcrumbs(props.presentation.header.breadcrumbs)"
    >
      <template #title>{{ props.presentation.header.title.text }}</template>
    </CadencePageHeading>

    <div v-bind="props.presentation.child_wrapper.attrs">
      <CatalogArtifactShow
        :artifact="props.presentation.artifact_show.artifact"
        :runs="props.presentation.artifact_show.runs"
        @reimport="emit('reimport')"
      />
    </div>
  </div>
</template>
