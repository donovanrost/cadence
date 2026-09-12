<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import { reactive, watch } from "vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceFormActions from "@cadence/ui/CadenceFormActions.vue";

import type {
  Page,
  DashboardForm,
  DashboardValues,
  DashboardPayload,
} from "./presentation.contracts";

const props = defineProps<{
  page: Page;
  form: DashboardForm;
  disabled?: boolean;
  preserveDraft?: boolean;
}>();

const emit = defineEmits<{
  validate: [payload: DashboardPayload];
  save: [payload: DashboardPayload];
}>();

const valuesFromForm = (form: DashboardForm): DashboardValues => ({
  name: form.name.value,
  description: form.description.value,
  document_json: form.document_json?.value ?? "",
});

const dashboard = reactive<DashboardValues>(valuesFromForm(props.form));
const pendingValidations: DashboardValues[] = [];

const values = (): DashboardValues => ({
  name: dashboard.name,
  description: dashboard.description,
  document_json: dashboard.document_json,
});

const sameValues = (left: DashboardValues, right: DashboardValues) =>
  left.name === right.name &&
  left.description === right.description &&
  left.document_json === right.document_json;

watch(
  () => props.form,
  (serverForm) => {
    if (props.preserveDraft) return;
    const serverValues = valuesFromForm(serverForm);
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues),
    );
    const latestPending = pendingValidations[pendingValidations.length - 1];
    const hasNewerTyping =
      acknowledgedIndex >= 0
        ? acknowledgedIndex < pendingValidations.length - 1
        : latestPending !== undefined && !sameValues(latestPending, serverValues);

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1);

    if (!hasNewerTyping) Object.assign(dashboard, serverValues);
  },
  { deep: true },
);

const payload = (): DashboardPayload => {
  const dashboardValues: DashboardPayload["dashboard"] = {
    name: dashboard.name,
    description: dashboard.description,
  };

  if (props.form.document_json !== null) {
    dashboardValues.document_json = dashboard.document_json;
  }

  return { dashboard: dashboardValues };
};

const validate = () => {
  if (props.disabled) return;
  if (!props.preserveDraft) pendingValidations.push(values());
  emit("validate", payload());
};

const save = () => {
  if (!props.disabled) emit("save", payload());
};
</script>

<template>
  <CadenceOpsViewport :id="page.id">
    <div class="">
      <CadencePageHeading
        ><template #title>{{ page.heading }}</template
        ><template #eyebrow>{{ page.eyebrow }}</template
        ><template #description>{{ page.description }}</template></CadencePageHeading
      >

      <div
        v-if="page.source !== null"
        :id="page.source.id"
        class="mt-6 border border-primary/20 bg-primary/5 p-3"
        :data-source-dashboard-id="page.source.dashboard_id"
      >
        <p class="hud-label">Source dashboard</p>
        <p class="mt-1 text-sm font-semibold">{{ page.source.name }}</p>
        <p class="mt-1 font-mono text-[0.65rem] text-base-content/45">
          {{ page.source.widget_count }} widgets · v{{ page.source.latest_version }}
        </p>
      </div>

      <form
        :id="form.id"
        class="mt-7 space-y-6 border border-base-300 bg-base-200/20 p-5"
        @submit.prevent="save"
      >
        <CadenceField
          :control-id="form.name.id"
          wrapper-class="fieldset mb-3"
          :label="form.name.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.name.id"
            :disabled="disabled"
            v-model="dashboard.name"
            :name="form.name.name"
            :type="form.name.type"
            :required="form.name.required"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <CadenceField
          :control-id="form.description.id"
          wrapper-class="fieldset mb-3"
          :label="form.description.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.description.id"
            :disabled="disabled"
            v-model="dashboard.description"
            :name="form.description.name"
            :type="form.description.type"
            :required="form.description.required"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <CadenceField
          v-if="form.document_json !== null"
          :control-id="form.document_json.id"
          wrapper-class="fieldset mb-3"
          :label="form.document_json.label"
          label-class="hud-label block mb-1.5"
        >
          <textarea
            :id="form.document_json.id"
            :disabled="disabled"
            v-model="dashboard.document_json"
            :name="form.document_json.name"
            :required="form.document_json.required"
            class="textarea textarea-bordered min-h-80 w-full font-mono text-xs"
            @input="validate"
          ></textarea>
        </CadenceField>

        <p v-if="page.import_guidance !== null" class="text-xs text-base-content/55">
          {{ page.import_guidance }}
        </p>

        <CadenceFormActions
          wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5"
        >
          <button :disabled="disabled" :id="form.submit.id" type="submit" class="btn btn-primary">
            {{ form.submit.label }}
          </button>
          <a
            :id="page.cancel.id"
            :href="page.cancel.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-ghost"
            >{{ page.cancel.label }}</a
          >
        </CadenceFormActions>
      </form>
    </div>
  </CadenceOpsViewport>
</template>
