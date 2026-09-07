<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { presentationBreadcrumbs } from "@cadence/ui/page-chrome";
import MissionApplications from "./MissionApplications.vue";

type Attrs = Record<string, string>;

type ElementPresentation = {
  attrs: Attrs;
};

type TextPresentation = ElementPresentation & {
  text: string;
};

type MissionApplicationsProps = InstanceType<typeof MissionApplications>["$props"];

type ApplicationEvent = {
  key: string;
};

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
    subtitle: TextPresentation;
  };
  applications_component: {
    attrs: Attrs;
    props: {
      applications: MissionApplicationsProps["applications"];
    };
  };
};

const props = defineProps<{ presentation: Presentation }>();

const emit = defineEmits<{
  install: [payload: ApplicationEvent];
  disable: [payload: ApplicationEvent];
  uninstall: [payload: ApplicationEvent];
}>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading
      :breadcrumbs="presentationBreadcrumbs(props.presentation.header.breadcrumbs)"
    >
      <template #title>{{ props.presentation.header.title.text }}</template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
    </CadencePageHeading>

    <div v-bind="props.presentation.applications_component.attrs">
      <MissionApplications
        :applications="props.presentation.applications_component.props.applications"
        @install="emit('install', $event)"
        @disable="emit('disable', $event)"
        @uninstall="emit('uninstall', $event)"
      />
    </div>
  </div>
</template>
