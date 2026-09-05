<script setup lang="ts">
import CommsGroundStationList from "./CommsGroundStationList.vue";
import CadenceEmptyState from "./ui/components/CadenceEmptyState.vue";
import CadencePageHeader from "./ui/components/CadencePageHeader.vue";
import type {
  Attrs,
  ElementPresentation,
  EmptyStatePresentation,
  PageHeaderAction,
  PageHeaderPresentation,
} from "./ui/components/page_shell";

type GroundStationListProps = InstanceType<typeof CommsGroundStationList>["$props"];

type Presentation = {
  root: ElementPresentation;
  header: PageHeaderPresentation & {
    actions: ElementPresentation & {
      new_ground_station: PageHeaderAction;
    };
  };
  empty_state: EmptyStatePresentation | null;
  card: {
    attrs: Attrs;
    body: ElementPresentation;
    list_component: {
      attrs: Attrs;
      props: {
        rows: GroundStationListProps["rows"];
        search: GroundStationListProps["search"];
        sort: GroundStationListProps["sort"];
        sort_dir: GroundStationListProps["sort_dir"];
        page: GroundStationListProps["page"];
        page_size: GroundStationListProps["page_size"];
        total_count: GroundStationListProps["total_count"];
      };
    };
  } | null;
};

const props = defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <CadencePageHeader
      :header="props.presentation.header"
      :action="props.presentation.header.actions.new_ground_station"
    />

    <CadenceEmptyState
      v-if="props.presentation.empty_state"
      :empty-state="props.presentation.empty_state"
    />

    <section v-else-if="props.presentation.card" v-bind="props.presentation.card.attrs">
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.list_component.attrs">
          <CommsGroundStationList
            :rows="props.presentation.card.list_component.props.rows"
            :search="props.presentation.card.list_component.props.search"
            :sort="props.presentation.card.list_component.props.sort"
            :sort_dir="props.presentation.card.list_component.props.sort_dir"
            :page="props.presentation.card.list_component.props.page"
            :page_size="props.presentation.card.list_component.props.page_size"
            :total_count="props.presentation.card.list_component.props.total_count"
          />
        </div>
      </div>
    </section>
  </div>
</template>
