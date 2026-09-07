<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { presentationBreadcrumbs } from "@cadence/ui/page-chrome";
import ProviderAccountCards from "./ProviderAccountCards.vue";

type RawAttrs = Record<string, string>;

type ElementPresentation = {
  attrs: RawAttrs;
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

type ProviderAccountCard = InstanceType<typeof ProviderAccountCards>["$props"]["card"] & {
  __dom_id: string;
};

type Presentation = {
  root: ElementPresentation;
  header: {
    attrs: RawAttrs;
    body: ElementPresentation;
    content: ElementPresentation;
    breadcrumbs: {
      attrs: RawAttrs;
      items: BreadcrumbItem[];
    };
    title: TextPresentation & {
      suffix: TextPresentation;
    };
    subtitle: TextPresentation;
    actions: {
      attrs: RawAttrs;
      new_account: TextPresentation & {
        icon: ElementPresentation;
      };
    };
  };
  empty_state: {
    attrs: RawAttrs;
    icon: ElementPresentation;
    title: TextPresentation;
    description: TextPresentation;
    action_container: ElementPresentation;
    action: TextPresentation & {
      icon: ElementPresentation;
    };
  } | null;
  stream: {
    attrs: RawAttrs;
    empty_marker: ElementPresentation;
  };
};

const props = defineProps<{
  presentation: Presentation;
  provider_accounts: ProviderAccountCard[];
}>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading
      :breadcrumbs="presentationBreadcrumbs(props.presentation.header.breadcrumbs)"
    >
      <template #title>{{ props.presentation.header.title.text }} </template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
      <template #metadata
        ><span>
          {{ props.presentation.header.title.suffix.text }}
        </span></template
      >
      <template #actions
        ><a v-bind="props.presentation.header.actions.new_account.attrs">
          <span v-bind="props.presentation.header.actions.new_account.icon.attrs"></span>
          {{ props.presentation.header.actions.new_account.text }}
        </a></template
      >
    </CadencePageHeading>

    <div v-if="props.presentation.empty_state" v-bind="props.presentation.empty_state.attrs">
      <span v-bind="props.presentation.empty_state.icon.attrs"></span>
      <p v-bind="props.presentation.empty_state.title.attrs">
        {{ props.presentation.empty_state.title.text }}
      </p>
      <p v-bind="props.presentation.empty_state.description.attrs">
        {{ props.presentation.empty_state.description.text }}
      </p>
      <div v-bind="props.presentation.empty_state.action_container.attrs">
        <a v-bind="props.presentation.empty_state.action.attrs">
          <span v-bind="props.presentation.empty_state.action.icon.attrs"></span>
          {{ props.presentation.empty_state.action.text }}
        </a>
      </div>
    </div>

    <div v-bind="props.presentation.stream.attrs">
      <div v-bind="props.presentation.stream.empty_marker.attrs"></div>
      <div v-for="card in props.provider_accounts" :id="card.__dom_id" :key="card.__dom_id">
        <div :id="`${card.__dom_id}-component`">
          <ProviderAccountCards :card="card" />
        </div>
      </div>
    </div>
  </div>
</template>
