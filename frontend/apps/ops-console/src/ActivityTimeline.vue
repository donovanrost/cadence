<script setup lang="ts">
import ActivityTimelineRow from "./ActivityTimelineRow.vue";
import DashboardActivityControls from "./DashboardActivityControls.vue";
import SelectedActivityEventSummary from "./SelectedActivityEventSummary.vue";

type Attributes = Record<string, string>;
type ClassValue = string | string[];
type ControlsPresentation = InstanceType<
  typeof DashboardActivityControls
>["$props"]["presentation"];
type SelectedActivityPresentation = InstanceType<
  typeof SelectedActivityEventSummary
>["$props"]["presentation"];
type RowPresentation = InstanceType<typeof ActivityTimelineRow>["$props"]["presentation"];

type TextPresentation = {
  class: string;
  text: string;
};

type ComparisonReviewActionPresentation = {
  root: {
    id: string;
    class: string;
    attrs: Attributes;
  };
  header: {
    class: string;
    content_class: string;
    title: TextPresentation;
    message: TextPresentation;
    status: {
      class: ClassValue;
      text: string;
      attrs: Attributes;
    };
  };
  fields: {
    visible: boolean;
    class: string;
    rows: Array<{
      key: string;
      order: number;
      label: TextPresentation;
      value: TextPresentation & { attrs: Attributes };
    }>;
  };
};

type Presentation = {
  root: {
    id: string;
    class: string;
    attrs: Attributes;
  };
  controls: ControlsPresentation;
  selected_activity: SelectedActivityPresentation | null;
  comparison_review_action: ComparisonReviewActionPresentation | null;
  list: {
    id: string;
    class: string;
    attrs: Attributes;
    rows: Array<{
      key: string;
      order: number;
      presentation: RowPresentation;
    }>;
  };
  queue_message: (TextPresentation & { attrs: Attributes }) | null;
  empty_states: Array<
    TextPresentation & {
      key: string;
      order: number;
      visible: boolean;
      attrs: Attributes;
    }
  >;
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <section
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <DashboardActivityControls :presentation="presentation.controls" />
    <SelectedActivityEventSummary
      v-if="presentation.selected_activity"
      :presentation="presentation.selected_activity"
    />

    <div
      v-if="presentation.comparison_review_action"
      :id="presentation.comparison_review_action.root.id"
      :class="presentation.comparison_review_action.root.class"
      v-bind="presentation.comparison_review_action.root.attrs"
    >
      <div :class="presentation.comparison_review_action.header.class">
        <div :class="presentation.comparison_review_action.header.content_class">
          <h4 :class="presentation.comparison_review_action.header.title.class">
            {{ presentation.comparison_review_action.header.title.text }}
          </h4>
          <p :class="presentation.comparison_review_action.header.message.class">
            {{ presentation.comparison_review_action.header.message.text }}
          </p>
        </div>
        <span
          :class="presentation.comparison_review_action.header.status.class"
          v-bind="presentation.comparison_review_action.header.status.attrs"
        >
          {{ presentation.comparison_review_action.header.status.text }}
        </span>
      </div>
      <dl
        v-if="presentation.comparison_review_action.fields.visible"
        :class="presentation.comparison_review_action.fields.class"
      >
        <template v-for="row in presentation.comparison_review_action.fields.rows" :key="row.key">
          <dt :class="row.label.class">{{ row.label.text }}</dt>
          <dd :class="row.value.class" v-bind="row.value.attrs">
            {{ row.value.text }}
          </dd>
        </template>
      </dl>
    </div>

    <ol
      :id="presentation.list.id"
      :class="presentation.list.class"
      v-bind="presentation.list.attrs"
    >
      <ActivityTimelineRow
        v-for="row in presentation.list.rows"
        :key="row.key"
        :presentation="row.presentation"
      />
    </ol>

    <p
      v-if="presentation.queue_message"
      :class="presentation.queue_message.class"
      v-bind="presentation.queue_message.attrs"
    >
      {{ presentation.queue_message.text }}
    </p>

    <template v-for="emptyState in presentation.empty_states" :key="emptyState.key">
      <p v-if="emptyState.visible" :class="emptyState.class" v-bind="emptyState.attrs">
        {{ emptyState.text }}
      </p>
    </template>
  </section>
</template>
