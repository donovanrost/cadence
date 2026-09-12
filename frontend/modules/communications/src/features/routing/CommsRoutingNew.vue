<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { reactive, watch } from "vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceFormActions from "@cadence/ui/CadenceFormActions.vue";
import CadenceFormSectionHeader from "@cadence/ui/CadenceFormSectionHeader.vue";
import CadenceFormSectionFrame from "@cadence/ui/CadenceFormSectionFrame.vue";
import CadenceFormPageFrame from "@cadence/ui/CadenceFormPageFrame.vue";
import FormFeedback from "../../shared/FormFeedback.vue";
import type { FormFeedback as Feedback } from "../../shared/form-workflow.contracts";

import type {
  Page,
  RoutingRuleForm,
  RoutingRuleOptions,
  RoutingRuleValues,
  RoutingRulePayload,
} from "./routing-new.contracts";

const props = defineProps<{
  page: Page;
  form: RoutingRuleForm;
  options: RoutingRuleOptions;
  feedback?: Feedback;
}>();

const emit = defineEmits<{
  validate: [payload: RoutingRulePayload];
  save: [payload: RoutingRulePayload];
}>();

const formValues = (form: RoutingRuleForm): RoutingRuleValues => ({
  display_name: form.fields.display_name.value,
  purpose_label: form.fields.purpose_label.value,
  spacecraft_id: form.fields.spacecraft_id.value,
  transport_ref: form.fields.transport_ref.value,
  direction: form.fields.direction.value,
  role: form.fields.role.value,
});

const values = reactive<RoutingRuleValues>(formValues(props.form));

watch(
  () => props.form,
  (serverForm) => {
    Object.assign(values, formValues(serverForm));
  },
  { deep: true },
);

const routingRuleValues = (): RoutingRuleValues => ({
  display_name: values.display_name,
  purpose_label: values.purpose_label,
  spacecraft_id: values.spacecraft_id,
  transport_ref: values.transport_ref,
  direction: values.direction,
  role: values.role,
});

const validate = () => {
  const routingRule = routingRuleValues();
  emit("validate", { routing_rule: routingRule });
};

const save = () => emit("save", { routing_rule: routingRuleValues() });
</script>

<template>
  <CadenceFormPageFrame :id="page.id">
    <CadencePageHeading :breadcrumbs="page.breadcrumbs">
      <template #title>{{ page.title }}</template>
      <template #description>{{ page.subtitle }}</template>
    </CadencePageHeading>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <CadenceFormSectionFrame id="routing-rule-intent-section">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.intent.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.intent.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.display_name.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.display_name.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.display_name.id"
            v-model="values.display_name"
            :name="form.fields.display_name.name"
            :type="form.fields.display_name.type"
            :required="form.fields.display_name.required"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <CadenceField
          :control-id="form.fields.purpose_label.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.purpose_label.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.purpose_label.id"
            v-model="values.purpose_label"
            :name="form.fields.purpose_label.name"
            :type="form.fields.purpose_label.type"
            :required="form.fields.purpose_label.required"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame id="routing-rule-transport-section">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.transport.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.transport.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.spacecraft_id.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.spacecraft_id.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.spacecraft_id.id"
            v-model="values.spacecraft_id"
            :name="form.fields.spacecraft_id.name"
            :required="form.fields.spacecraft_id.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.spacecraft"
              :key="`${option.value}-${option.label}`"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>

        <CadenceField
          :control-id="form.fields.transport_ref.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.transport_ref.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.transport_ref.id"
            v-model="values.transport_ref"
            :name="form.fields.transport_ref.name"
            :required="form.fields.transport_ref.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.transports"
              :key="`${option.value}-${option.label}`"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame id="routing-rule-policy-section">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.policy.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.policy.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.direction.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.direction.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.direction.id"
            v-model="values.direction"
            :name="form.fields.direction.name"
            :required="form.fields.direction.required"
            class="w-full select"
            @change="validate"
          >
            <option v-for="option in options.directions" :key="option.value" :value="option.value">
              {{ option.label }}
            </option>
          </select>
        </CadenceField>

        <CadenceField
          :control-id="form.fields.role.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.role.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.role.id"
            v-model="values.role"
            :name="form.fields.role.name"
            :required="form.fields.role.required"
            class="w-full select"
            @change="validate"
          >
            <option v-for="option in options.roles" :key="option.value" :value="option.value">
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button
          :id="form.actions.submit.id"
          type="submit"
          class="btn btn-primary"
          :disabled="feedback && !feedback.canSubmit"
        >
          {{ form.actions.submit.label }}
        </button>
        <a
          :id="form.actions.cancel.id"
          :href="form.actions.cancel.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-ghost"
          >{{ form.actions.cancel.label }}</a
        >
      </CadenceFormActions>
      <FormFeedback
        :id="form.id + '-feedback'"
        v-bind="feedback ? { feedback } : {}"
        @retry="validate"
      />
    </form>
  </CadenceFormPageFrame>
</template>
