<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import SpacecraftTypeList from "./SpacecraftTypeList.vue";
import CadenceEmptyState from "@cadence/ui/CadenceEmptyState.vue";
import CadencePageHeader from "@cadence/ui/CadencePageHeader.vue";
import type {
  Attrs,
  ElementPresentation,
  EmptyStatePresentation,
  PageHeaderAction,
  PageHeaderPresentation,
} from "@cadence/ui/page_shell";

type SpacecraftTypeListProps = InstanceType<typeof SpacecraftTypeList>["$props"];

type Presentation = {
  root: ElementPresentation;
  header: PageHeaderPresentation & {
    actions: ElementPresentation & {
      new_profile: PageHeaderAction;
    };
  };
  empty_state: EmptyStatePresentation | null;
  card: {
    attrs: Attrs;
    body: ElementPresentation;
    list_component: ElementPresentation;
    rows: SpacecraftTypeListProps["rows"];
  } | null;
};

const props = defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeader
      :header="props.presentation.header"
      :action="props.presentation.header.actions.new_profile"
    />

    <CadenceEmptyState
      v-if="props.presentation.empty_state"
      :empty-state="props.presentation.empty_state"
    />

    <section v-if="props.presentation.card" v-bind="props.presentation.card.attrs">
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.list_component.attrs">
          <SpacecraftTypeList :rows="props.presentation.card.rows" />
        </div>
      </div>
    </section>
  </div>
</template>
