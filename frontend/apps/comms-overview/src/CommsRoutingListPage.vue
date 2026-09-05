<script setup lang="ts">
import CommsRoutingList from "./CommsRoutingList.vue";
import CadenceEmptyState from "./ui/components/CadenceEmptyState.vue";
import CadencePageHeader from "./ui/components/CadencePageHeader.vue";
import type {
  Attrs,
  ElementPresentation,
  EmptyStatePresentation,
  PageHeaderAction,
  PageHeaderPresentation,
} from "./ui/components/page_shell";

type CommsRoutingListProps = InstanceType<typeof CommsRoutingList>["$props"];

type Presentation = {
  root: ElementPresentation;
  header: PageHeaderPresentation & {
    actions: ElementPresentation & {
      new_rule: PageHeaderAction;
    };
  };
  empty_state: EmptyStatePresentation | null;
  card: {
    attrs: Attrs;
    body: ElementPresentation;
    list_component: ElementPresentation;
    rows: CommsRoutingListProps["rows"];
  } | null;
};

const props = defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <CadencePageHeader
      :header="props.presentation.header"
      :action="props.presentation.header.actions.new_rule"
    />

    <CadenceEmptyState
      v-if="props.presentation.empty_state"
      :empty-state="props.presentation.empty_state"
    />

    <section v-if="props.presentation.card" v-bind="props.presentation.card.attrs">
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.list_component.attrs">
          <CommsRoutingList :rows="props.presentation.card.rows" />
        </div>
      </div>
    </section>
  </div>
</template>
