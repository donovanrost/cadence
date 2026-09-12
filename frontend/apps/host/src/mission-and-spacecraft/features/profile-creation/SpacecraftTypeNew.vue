<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { reactive } from "vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceFormActions from "@cadence/ui/CadenceFormActions.vue";
import CadenceFormSectionHeader from "@cadence/ui/CadenceFormSectionHeader.vue";
import CadenceFormSectionFrame from "@cadence/ui/CadenceFormSectionFrame.vue";
import CadenceFormPageFrame from "@cadence/ui/CadenceFormPageFrame.vue";

import type {
  ProfileData,
  ProfileErrors,
  ProfileForm,
  ProfileOptions,
  ProfilePayload,
  ProfileValues,
} from "./contracts";
const props = withDefaults(
  defineProps<ProfileData & { disabled?: boolean; errors?: ProfileErrors }>(),
  { disabled: false, errors: () => ({}) },
);
const emit = defineEmits<{
  validate: [payload: ProfilePayload];
  save: [payload: ProfilePayload];
}>();
const formValues = (form: ProfileForm): ProfileValues => ({
  display_name: form.fields.display_name.value,
  downlink_protocol: form.fields.downlink_protocol.value,
  uplink_protocol: form.fields.uplink_protocol.value,
  frame_size: form.fields.frame_size.value,
  secondary_header_length: form.fields.secondary_header_length.value,
  insert_zone_length: form.fields.insert_zone_length.value,
  truncated_primary_header: form.fields.truncated_primary_header.value,
  ocf_length: form.fields.ocf_length.value,
  applications: { ...form.fields.applications.value },
});

const values = reactive<ProfileValues>(formValues(props.form));
const profileValues = (): ProfileValues => ({
  ...values,
  applications: { ...values.applications },
});
const validate = () => {
  if (!props.disabled) emit("validate", { spacecraft_type: profileValues() });
};
const save = () => {
  if (!props.disabled) emit("save", { spacecraft_type: profileValues() });
};
const applicationSelected = (key: string) => Object.hasOwn(values.applications, key);
const frameFieldVisible = (field: keyof ProfileOptions["frame_fields"]) =>
  props.options.frame_fields[field].includes(values.downlink_protocol);
function toggleApplication(key: string, event: Event) {
  if (
    props.disabled ||
    !props.applications.some((application) => application.key === key && application.available)
  )
    return;
  if ((event.target as HTMLInputElement).checked) values.applications[key] = "1";
  else delete values.applications[key];
  validate();
}
</script>
<template>
  <CadenceFormPageFrame :id="page.id">
    <CadencePageHeading :breadcrumbs="page.breadcrumbs">
      <template #title>{{ page.title }}</template>
      <template #description>{{ page.subtitle }}</template>
    </CadencePageHeading>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <div
        v-if="Object.keys(errors).length"
        id="profile-validation-errors"
        role="alert"
        class="border border-error/40 bg-error/10 p-4 text-sm text-error"
      >
        <div
          v-for="(messages, field) in errors"
          :id="form.fields[field].id + '-errors'"
          :key="field"
        >
          <p v-for="message in messages" :key="message">{{ message }}</p>
        </div>
      </div>
      <CadenceFormSectionFrame :id="form.sections.identity.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.identity.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.identity.title"
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
            :disabled="disabled"
            :aria-invalid="errors.display_name?.length ? 'true' : undefined"
            :aria-describedby="
              errors.display_name?.length ? form.fields.display_name.id + '-errors' : undefined
            "
            v-model="values.display_name"
            :name="form.fields.display_name.name"
            :type="form.fields.display_name.type"
            :required="form.fields.display_name.required"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.protocols.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.protocols.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.protocols.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.downlink_protocol.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.downlink_protocol.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.downlink_protocol.id"
            :disabled="disabled"
            :aria-invalid="errors.downlink_protocol?.length ? 'true' : undefined"
            :aria-describedby="
              errors.downlink_protocol?.length
                ? form.fields.downlink_protocol.id + '-errors'
                : undefined
            "
            v-model="values.downlink_protocol"
            :name="form.fields.downlink_protocol.name"
            :required="form.fields.downlink_protocol.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.downlink_protocols"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>

        <CadenceField
          :control-id="form.fields.uplink_protocol.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.uplink_protocol.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.uplink_protocol.id"
            :disabled="disabled"
            :aria-invalid="errors.uplink_protocol?.length ? 'true' : undefined"
            :aria-describedby="
              errors.uplink_protocol?.length
                ? form.fields.uplink_protocol.id + '-errors'
                : undefined
            "
            v-model="values.uplink_protocol"
            :name="form.fields.uplink_protocol.name"
            :required="form.fields.uplink_protocol.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.uplink_protocols"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.frame_parameters.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.frame_parameters.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.frame_parameters.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <p class="text-sm text-base-content/70">
          {{ form.sections.frame_parameters.description }}
        </p>

        <CadenceField
          :control-id="form.fields.frame_size.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.frame_size.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.frame_size.id"
            :disabled="disabled"
            :aria-invalid="errors.frame_size?.length ? 'true' : undefined"
            :aria-describedby="
              errors.frame_size?.length ? form.fields.frame_size.id + '-errors' : undefined
            "
            v-model="values.frame_size"
            :name="form.fields.frame_size.name"
            :type="form.fields.frame_size.type"
            :required="form.fields.frame_size.required"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <CadenceField
          v-if="frameFieldVisible('secondary_header_length')"
          :control-id="form.fields.secondary_header_length.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.secondary_header_length.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.secondary_header_length.id"
            :disabled="disabled"
            :aria-invalid="errors.secondary_header_length?.length ? 'true' : undefined"
            :aria-describedby="
              errors.secondary_header_length?.length
                ? form.fields.secondary_header_length.id + '-errors'
                : undefined
            "
            v-model="values.secondary_header_length"
            :name="form.fields.secondary_header_length.name"
            :type="form.fields.secondary_header_length.type"
            :required="form.fields.secondary_header_length.required"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <CadenceField
          v-if="frameFieldVisible('insert_zone_length')"
          :control-id="form.fields.insert_zone_length.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.insert_zone_length.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.insert_zone_length.id"
            :disabled="disabled"
            :aria-invalid="errors.insert_zone_length?.length ? 'true' : undefined"
            :aria-describedby="
              errors.insert_zone_length?.length
                ? form.fields.insert_zone_length.id + '-errors'
                : undefined
            "
            v-model="values.insert_zone_length"
            :name="form.fields.insert_zone_length.name"
            :type="form.fields.insert_zone_length.type"
            :required="form.fields.insert_zone_length.required"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <CadenceField
          v-if="frameFieldVisible('truncated_primary_header')"
          :control-id="form.fields.truncated_primary_header.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.truncated_primary_header.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.truncated_primary_header.id"
            :disabled="disabled"
            :aria-invalid="errors.truncated_primary_header?.length ? 'true' : undefined"
            :aria-describedby="
              errors.truncated_primary_header?.length
                ? form.fields.truncated_primary_header.id + '-errors'
                : undefined
            "
            v-model="values.truncated_primary_header"
            :name="form.fields.truncated_primary_header.name"
            :required="form.fields.truncated_primary_header.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.truncated_primary_headers"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>

        <CadenceField
          :control-id="form.fields.ocf_length.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.ocf_length.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.ocf_length.id"
            :disabled="disabled"
            :aria-invalid="errors.ocf_length?.length ? 'true' : undefined"
            :aria-describedby="
              errors.ocf_length?.length ? form.fields.ocf_length.id + '-errors' : undefined
            "
            v-model="values.ocf_length"
            :name="form.fields.ocf_length.name"
            :required="form.fields.ocf_length.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options.operational_control_fields"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.applications.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.applications.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.applications.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <p class="text-sm text-base-content/70">
          {{ form.sections.applications.description }}
        </p>

        <div :id="form.fields.applications.id" class="space-y-3">
          <label
            v-for="application in applications"
            :key="application.key"
            :class="[
              'flex items-start gap-3 rounded border p-3 transition-colors',
              application.available
                ? 'border-base-300 bg-base-100/40 border-l-2 border-l-primary/40 hover:border-l-primary cursor-pointer'
                : 'border-base-300/50 bg-base-100/20 opacity-50 cursor-not-allowed',
            ]"
          >
            <input
              :id="application.id"
              type="checkbox"
              :name="application.name"
              :value="application.value"
              :checked="applicationSelected(application.key)"
              :disabled="disabled || !application.available"
              class="checkbox checkbox-primary mt-0.5"
              @change="toggleApplication(application.key, $event)"
            />
            <div>
              <div class="font-medium text-base-content">
                {{ application.label }}
                <span v-if="application.availability_label" class="hud-label ml-2">
                  {{ application.availability_label }}
                </span>
              </div>
              <p class="mt-0.5 text-sm text-base-content/70">{{ application.description }}</p>
            </div>
          </label>
        </div>
      </CadenceFormSectionFrame>

      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button
          :id="form.actions.submit.id"
          type="submit"
          class="btn btn-primary"
          :disabled="disabled"
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
    </form>
  </CadenceFormPageFrame>
</template>
