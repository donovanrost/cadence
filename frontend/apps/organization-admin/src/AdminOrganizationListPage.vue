<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import AdminOrganizationList from "./AdminOrganizationList.vue";
import CadenceEmptyState from "@cadence/ui/CadenceEmptyState.vue";
import CadencePageHeader from "@cadence/ui/CadencePageHeader.vue";
import type {
  CompactPageHeaderPresentation,
  ElementPresentation,
  EmptyStatePresentation,
  TextPresentation,
} from "@cadence/ui/page_shell";

type OrganizationRow = {
  id: string;
  display_name: string;
  slug: string;
  href: string;
};

type BreadcrumbItem = {
  separator: TextPresentation | null;
  kind: "link" | "current";
  content: TextPresentation;
};

type AdminOrganizationListPresentation = {
  root: ElementPresentation;
  header: {
    root: ElementPresentation;
    layout: ElementPresentation;
    content: ElementPresentation;
    breadcrumbs: {
      root: ElementPresentation;
      items: BreadcrumbItem[];
    };
    title: TextPresentation;
    actions: ElementPresentation;
    create_action: TextPresentation;
  };
  empty_state: {
    root: ElementPresentation;
    title: TextPresentation;
    description: TextPresentation;
    action_container: ElementPresentation;
    action: TextPresentation;
    action_icon: ElementPresentation;
  } | null;
  card: {
    root: ElementPresentation;
    body: ElementPresentation;
    child: ElementPresentation;
    rows: OrganizationRow[];
  } | null;
};

const props = defineProps<{ presentation: AdminOrganizationListPresentation }>();

const headerPresentation = (
  header: AdminOrganizationListPresentation["header"],
): CompactPageHeaderPresentation => ({
  attrs: header.root.attrs,
  body: header.layout,
  content: header.content,
  breadcrumbs: {
    attrs: header.breadcrumbs.root.attrs,
    items: header.breadcrumbs.items.map((breadcrumb) => ({
      key: breadcrumb.content.text,
      separator: breadcrumb.separator,
      link: breadcrumb.kind === "link" ? breadcrumb.content : null,
      current: breadcrumb.kind === "current" ? breadcrumb.content : null,
    })),
  },
  title: header.title,
  actions: header.actions,
});

const emptyStatePresentation = (
  emptyState: NonNullable<AdminOrganizationListPresentation["empty_state"]>,
): EmptyStatePresentation => ({
  attrs: emptyState.root.attrs,
  title: emptyState.title,
  description: emptyState.description,
  action_container: emptyState.action_container,
  action: {
    ...emptyState.action,
    icon: emptyState.action_icon,
  },
});
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeader
      :header="headerPresentation(props.presentation.header)"
      :action="props.presentation.header.create_action"
    />

    <CadenceEmptyState
      v-if="props.presentation.empty_state"
      :empty-state="emptyStatePresentation(props.presentation.empty_state)"
    />

    <section v-if="props.presentation.card" v-bind="props.presentation.card.root.attrs">
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.child.attrs">
          <AdminOrganizationList :rows="props.presentation.card.rows" />
        </div>
      </div>
    </section>
  </div>
</template>
