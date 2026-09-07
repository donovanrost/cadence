<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { presentationBreadcrumbs } from "@cadence/ui/page-chrome";
import SpacecraftApplications from "./SpacecraftApplications.vue";

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

type ApplicationEvent = {
  key: string;
};

type SpacecraftApplicationsProps = InstanceType<typeof SpacecraftApplications>["$props"];

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
    actions: {
      attrs: Attrs;
      readiness: TextPresentation;
    };
  };
  component: ElementPresentation;
  profile: SpacecraftApplicationsProps["profile"];
  applications: SpacecraftApplicationsProps["applications"];
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
      <template #actions
        ><a v-bind="props.presentation.header.actions.readiness.attrs">
          {{ props.presentation.header.actions.readiness.text }}
        </a></template
      >
    </CadencePageHeading>

    <div v-bind="props.presentation.component.attrs">
      <SpacecraftApplications
        :profile="props.presentation.profile"
        :applications="props.presentation.applications"
        @install="emit('install', $event)"
        @disable="emit('disable', $event)"
        @uninstall="emit('uninstall', $event)"
      />
    </div>
  </div>
</template>
