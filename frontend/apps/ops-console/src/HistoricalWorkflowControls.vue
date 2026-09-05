<script setup lang="ts">
import HistoricalWorkflowActionExplanations from "./HistoricalWorkflowActionExplanations.vue";
import HistoricalWorkflowCorrectionForm from "./HistoricalWorkflowCorrectionForm.vue";
import HistoricalWorkflowGroupForm from "./HistoricalWorkflowGroupForm.vue";
import HistoricalWorkflowGroupStatus from "./HistoricalWorkflowGroupStatus.vue";
import HistoricalWorkflowJobStatus from "./HistoricalWorkflowJobStatus.vue";
import HistoricalWorkflowLatestAction from "./HistoricalWorkflowLatestAction.vue";
import HistoricalWorkflowStageForm from "./HistoricalWorkflowStageForm.vue";

type Attributes = Record<string, string>;
type ChildPresentation = Record<string, unknown>;

type Presentation = {
  root: {
    id: string;
    class: string;
    attrs: Attributes;
  };
  heading: {
    class: string;
    text: string;
  };
  action_outcome: null | {
    root: {
      id: string;
      class: string;
      attrs: Attributes;
    };
    message: string | null;
  };
  latest_action: ChildPresentation | null;
  action_explanations: ChildPresentation | null;
  group_status: ChildPresentation | null;
  job_status: ChildPresentation | null;
  correction_form: ChildPresentation | null;
  stage_form: ChildPresentation;
  group_form: ChildPresentation | null;
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <section
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <h3 :class="presentation.heading.class">{{ presentation.heading.text }}</h3>

    <div
      v-if="presentation.action_outcome"
      :id="presentation.action_outcome.root.id"
      :class="presentation.action_outcome.root.class"
      v-bind="presentation.action_outcome.root.attrs"
    >
      {{ presentation.action_outcome.message }}
    </div>

    <HistoricalWorkflowLatestAction
      v-if="presentation.latest_action"
      :presentation="presentation.latest_action"
    />
    <HistoricalWorkflowActionExplanations
      v-if="presentation.action_explanations"
      :presentation="presentation.action_explanations"
    />
    <HistoricalWorkflowGroupStatus
      v-if="presentation.group_status"
      :presentation="presentation.group_status"
    />
    <HistoricalWorkflowJobStatus
      v-if="presentation.job_status"
      :presentation="presentation.job_status"
    />
    <HistoricalWorkflowCorrectionForm
      v-if="presentation.correction_form"
      :presentation="presentation.correction_form"
    />
    <HistoricalWorkflowStageForm :presentation="presentation.stage_form" />
    <HistoricalWorkflowGroupForm
      v-if="presentation.group_form"
      :presentation="presentation.group_form"
    />
  </section>
</template>
