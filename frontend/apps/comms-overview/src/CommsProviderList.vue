<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { presentationBreadcrumbs } from "@cadence/ui/page-chrome";
import CommsProviderTable from "./CommsProviderTable.vue";

type Attrs = Record<string, string>;

type ElementPresentation = {
  attrs: Attrs;
};

type TextPresentation = ElementPresentation & {
  text: string;
};

type ProviderRow = {
  id: string;
  display_name: string;
  provider_type: string;
  server_url: string;
  status: "ready" | "attention" | "blocked";
  status_label: string;
  account_binding: string;
  grant_binding: string;
  last_synced_at: string;
  version: string;
  href: string;
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
    title: TextPresentation & {
      suffix: TextPresentation;
    };
    subtitle: TextPresentation;
    actions: {
      attrs: Attrs;
      new_provider: TextPresentation & {
        icon: ElementPresentation;
      };
    };
  };
  empty_state: {
    attrs: Attrs;
    title: TextPresentation;
    description: TextPresentation;
    action_container: ElementPresentation;
    action: TextPresentation & {
      icon: ElementPresentation;
    };
  } | null;
  card: {
    attrs: Attrs;
    body: ElementPresentation;
    table_component: ElementPresentation;
    rows: ProviderRow[];
  } | null;
};

const props = defineProps<{ presentation: Presentation }>();
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
        ><a v-bind="props.presentation.header.actions.new_provider.attrs">
          <span v-bind="props.presentation.header.actions.new_provider.icon.attrs"></span>
          {{ props.presentation.header.actions.new_provider.text }}
        </a></template
      >
    </CadencePageHeading>

    <div v-if="props.presentation.empty_state" v-bind="props.presentation.empty_state.attrs">
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

    <section v-else-if="props.presentation.card" v-bind="props.presentation.card.attrs">
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.table_component.attrs">
          <CommsProviderTable :rows="props.presentation.card.rows" />
        </div>
      </div>
    </section>
  </div>
</template>
