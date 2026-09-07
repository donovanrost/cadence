<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import { computed, reactive, watch } from "vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";

type Option = {
  label: string;
  value: string;
};

type FormField = {
  id: string;
  name: string;
  type: "datetime-local" | "number" | "select" | "text" | "textarea";
  label: string;
  required: boolean;
  value: string;
  options?: Option[];
  min?: string;
  placeholder?: string;
  maxlength?: string;
};

type FieldName =
  | "spacecraft_id"
  | "contact_intent"
  | "earliest_start"
  | "latest_end"
  | "success_measure"
  | "minimum_duration_seconds"
  | "preferred_duration_seconds"
  | "minimum_data_volume_bytes"
  | "contact_count"
  | "minimum_separation_seconds"
  | "priority"
  | "allowed_providers"
  | "excluded_providers"
  | "allowed_stations"
  | "excluded_stations"
  | "rationale";

type ContactRequirementValues = Record<FieldName, string>;

type Page = {
  id: string;
  eyebrow: string;
  heading: string;
  description: string;
};

type JourneySection = {
  id: string;
  step: string;
  title: string;
  copy: string;
};

type ProgressiveSection = {
  id: string;
  visible: boolean;
  visible_for: string[];
};

type Journey = {
  outcome: JourneySection;
  horizon: JourneySection;
  advanced: {
    id: string;
    title: string;
    copy: string;
  };
  rationale: { id: string };
  progressive: {
    minimum_data_volume: ProgressiveSection;
    minimum_duration: ProgressiveSection;
  };
};

type ContactRequirementForm = {
  id: string;
  fields: Record<FieldName, FormField>;
  error: {
    id: string;
    message: string;
  } | null;
};

type Actions = {
  back: {
    id: string;
    label: string;
    href: string;
    icon: string;
  };
  cancel: {
    id: string;
    label: string;
    href: string;
  };
  submit: {
    id: string;
    label: string;
  };
};

type ContactRequirementPayload = {
  contact_requirement: ContactRequirementValues;
};

const props = defineProps<{
  page: Page;
  journey: Journey;
  form: ContactRequirementForm;
  actions: Actions;
}>();

const emit = defineEmits<{
  validate: [payload: ContactRequirementPayload];
  save: [payload: ContactRequirementPayload];
}>();

const fieldNames: FieldName[] = [
  "spacecraft_id",
  "contact_intent",
  "earliest_start",
  "latest_end",
  "success_measure",
  "minimum_duration_seconds",
  "preferred_duration_seconds",
  "minimum_data_volume_bytes",
  "contact_count",
  "minimum_separation_seconds",
  "priority",
  "allowed_providers",
  "excluded_providers",
  "allowed_stations",
  "excluded_stations",
  "rationale",
];

const valuesFromForm = (form: ContactRequirementForm): ContactRequirementValues => ({
  spacecraft_id: form.fields.spacecraft_id.value,
  contact_intent: form.fields.contact_intent.value,
  earliest_start: form.fields.earliest_start.value,
  latest_end: form.fields.latest_end.value,
  success_measure: form.fields.success_measure.value,
  minimum_duration_seconds: form.fields.minimum_duration_seconds.value,
  preferred_duration_seconds: form.fields.preferred_duration_seconds.value,
  minimum_data_volume_bytes: form.fields.minimum_data_volume_bytes.value,
  contact_count: form.fields.contact_count.value,
  minimum_separation_seconds: form.fields.minimum_separation_seconds.value,
  priority: form.fields.priority.value,
  allowed_providers: form.fields.allowed_providers.value,
  excluded_providers: form.fields.excluded_providers.value,
  allowed_stations: form.fields.allowed_stations.value,
  excluded_stations: form.fields.excluded_stations.value,
  rationale: form.fields.rationale.value,
});

const contactRequirement = reactive<ContactRequirementValues>(valuesFromForm(props.form));
const pendingValidations: ContactRequirementValues[] = [];

const values = (): ContactRequirementValues => ({
  spacecraft_id: contactRequirement.spacecraft_id,
  contact_intent: contactRequirement.contact_intent,
  earliest_start: contactRequirement.earliest_start,
  latest_end: contactRequirement.latest_end,
  success_measure: contactRequirement.success_measure,
  minimum_duration_seconds: contactRequirement.minimum_duration_seconds,
  preferred_duration_seconds: contactRequirement.preferred_duration_seconds,
  minimum_data_volume_bytes: contactRequirement.minimum_data_volume_bytes,
  contact_count: contactRequirement.contact_count,
  minimum_separation_seconds: contactRequirement.minimum_separation_seconds,
  priority: contactRequirement.priority,
  allowed_providers: contactRequirement.allowed_providers,
  excluded_providers: contactRequirement.excluded_providers,
  allowed_stations: contactRequirement.allowed_stations,
  excluded_stations: contactRequirement.excluded_stations,
  rationale: contactRequirement.rationale,
});

const sameValues = (left: ContactRequirementValues, right: ContactRequirementValues) =>
  fieldNames.every((field) => left[field] === right[field]);

watch(
  () => props.form,
  (serverForm) => {
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
    if (!hasNewerTyping) Object.assign(contactRequirement, serverValues);
  },
  { deep: true },
);

const payload = (): ContactRequirementPayload => ({ contact_requirement: values() });

const validate = () => {
  const currentValues = values();
  pendingValidations.push(currentValues);
  emit("validate", { contact_requirement: currentValues });
};

const save = () => emit("save", payload());

const progressiveVisible = (section: ProgressiveSection) => {
  const serverSuccessMeasure = props.form.fields.success_measure.value;

  return contactRequirement.success_measure === serverSuccessMeasure
    ? section.visible
    : section.visible_for.includes(contactRequirement.success_measure);
};

const activeError = computed(() =>
  sameValues(values(), valuesFromForm(props.form)) ? props.form.error : null,
);
</script>

<template>
  <CadenceOpsViewport :id="page.id">
    <CadencePageHeading>
      <template #title>{{ page.heading }}</template>
      <template #eyebrow>{{ page.eyebrow }}</template>
      <template #description>{{ page.description }}</template>
      <template #actions
        ><a
          :id="actions.back.id"
          :href="actions.back.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
        >
          <span :class="[actions.back.icon, 'h-3.5 w-3.5']"></span>
          {{ actions.back.label }}
        </a></template
      >
    </CadencePageHeading>

    <div class="">
      <form :id="form.id" class="space-y-5" @submit.prevent="save">
        <CadencePanel
          :id="journey.outcome.id"
          class="border border-base-300 bg-base-200/20"
          header-class="border-b border-base-300 px-5 py-3"
        >
          <template #header>
            <p class="hud-label">{{ journey.outcome.step }} / {{ journey.outcome.title }}</p>
            <p class="mt-1 text-sm text-base-content/55">{{ journey.outcome.copy }}</p>
          </template>
          <div class="grid gap-x-5 p-5 md:grid-cols-2">
            <CadenceField
              :control-id="form.fields.spacecraft_id.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.spacecraft_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="form.fields.spacecraft_id.id"
                v-model="contactRequirement.spacecraft_id"
                :name="form.fields.spacecraft_id.name"
                :required="form.fields.spacecraft_id.required"
                class="w-full select"
                @change="validate"
              >
                <option
                  v-for="option in form.fields.spacecraft_id.options ?? []"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>

            <CadenceField
              :control-id="form.fields.contact_intent.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.contact_intent.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="form.fields.contact_intent.id"
                v-model="contactRequirement.contact_intent"
                :name="form.fields.contact_intent.name"
                :required="form.fields.contact_intent.required"
                class="w-full select"
                @change="validate"
              >
                <option
                  v-for="option in form.fields.contact_intent.options ?? []"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>

            <CadenceField
              :control-id="form.fields.success_measure.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.success_measure.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="form.fields.success_measure.id"
                v-model="contactRequirement.success_measure"
                :name="form.fields.success_measure.name"
                :required="form.fields.success_measure.required"
                class="w-full select"
                @change="validate"
              >
                <option
                  v-for="option in form.fields.success_measure.options ?? []"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>

            <CadenceField
              :control-id="form.fields.priority.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.priority.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="form.fields.priority.id"
                v-model="contactRequirement.priority"
                :name="form.fields.priority.name"
                :required="form.fields.priority.required"
                class="w-full select"
                @change="validate"
              >
                <option
                  v-for="option in form.fields.priority.options ?? []"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
          </div>
        </CadencePanel>

        <CadencePanel
          :id="journey.horizon.id"
          class="border border-base-300 bg-base-200/20"
          header-class="border-b border-base-300 px-5 py-3"
        >
          <template #header>
            <p class="hud-label">{{ journey.horizon.step }} / {{ journey.horizon.title }}</p>
            <p class="mt-1 text-sm text-base-content/55">{{ journey.horizon.copy }}</p>
          </template>
          <div class="grid gap-x-5 p-5 md:grid-cols-2">
            <CadenceField
              :control-id="form.fields.earliest_start.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.earliest_start.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.earliest_start.id"
                v-model="contactRequirement.earliest_start"
                :name="form.fields.earliest_start.name"
                :type="form.fields.earliest_start.type"
                :required="form.fields.earliest_start.required"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>

            <CadenceField
              :control-id="form.fields.latest_end.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.latest_end.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.latest_end.id"
                v-model="contactRequirement.latest_end"
                :name="form.fields.latest_end.name"
                :type="form.fields.latest_end.type"
                :required="form.fields.latest_end.required"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>

            <div
              v-if="progressiveVisible(journey.progressive.minimum_data_volume)"
              :id="journey.progressive.minimum_data_volume.id"
            >
              <CadenceField
                :control-id="form.fields.minimum_data_volume_bytes.id"
                wrapper-class="fieldset mb-3"
                :label="form.fields.minimum_data_volume_bytes.label"
                label-class="hud-label block mb-1.5"
              >
                <input
                  :id="form.fields.minimum_data_volume_bytes.id"
                  v-model="contactRequirement.minimum_data_volume_bytes"
                  :name="form.fields.minimum_data_volume_bytes.name"
                  :type="form.fields.minimum_data_volume_bytes.type"
                  :required="form.fields.minimum_data_volume_bytes.required"
                  :min="form.fields.minimum_data_volume_bytes.min"
                  class="w-full input"
                  @input="validate"
                />
              </CadenceField>
            </div>

            <div
              v-if="progressiveVisible(journey.progressive.minimum_duration)"
              :id="journey.progressive.minimum_duration.id"
            >
              <CadenceField
                :control-id="form.fields.minimum_duration_seconds.id"
                wrapper-class="fieldset mb-3"
                :label="form.fields.minimum_duration_seconds.label"
                label-class="hud-label block mb-1.5"
              >
                <input
                  :id="form.fields.minimum_duration_seconds.id"
                  v-model="contactRequirement.minimum_duration_seconds"
                  :name="form.fields.minimum_duration_seconds.name"
                  :type="form.fields.minimum_duration_seconds.type"
                  :required="form.fields.minimum_duration_seconds.required"
                  :min="form.fields.minimum_duration_seconds.min"
                  class="w-full input"
                  @input="validate"
                />
              </CadenceField>
            </div>

            <CadenceField
              :control-id="form.fields.preferred_duration_seconds.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.preferred_duration_seconds.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.preferred_duration_seconds.id"
                v-model="contactRequirement.preferred_duration_seconds"
                :name="form.fields.preferred_duration_seconds.name"
                :type="form.fields.preferred_duration_seconds.type"
                :required="form.fields.preferred_duration_seconds.required"
                :min="form.fields.preferred_duration_seconds.min"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>

            <CadenceField
              :control-id="form.fields.contact_count.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.contact_count.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.contact_count.id"
                v-model="contactRequirement.contact_count"
                :name="form.fields.contact_count.name"
                :type="form.fields.contact_count.type"
                :required="form.fields.contact_count.required"
                :min="form.fields.contact_count.min"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>

            <CadenceField
              :control-id="form.fields.minimum_separation_seconds.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.minimum_separation_seconds.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.minimum_separation_seconds.id"
                v-model="contactRequirement.minimum_separation_seconds"
                :name="form.fields.minimum_separation_seconds.name"
                :type="form.fields.minimum_separation_seconds.type"
                :required="form.fields.minimum_separation_seconds.required"
                :min="form.fields.minimum_separation_seconds.min"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>
          </div>
        </CadencePanel>

        <CadenceDetailsFrame
          :id="journey.advanced.id"
          class="border border-base-300 bg-base-200/20"
        >
          <summary class="cursor-pointer px-5 py-4 text-sm font-semibold">
            {{ journey.advanced.title }}
            <span class="ml-2 font-normal text-base-content/45">{{ journey.advanced.copy }}</span>
          </summary>
          <div class="grid gap-x-5 border-t border-base-300 p-5 md:grid-cols-2">
            <CadenceField
              :control-id="form.fields.allowed_providers.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.allowed_providers.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.allowed_providers.id"
                v-model="contactRequirement.allowed_providers"
                :name="form.fields.allowed_providers.name"
                :type="form.fields.allowed_providers.type"
                :required="form.fields.allowed_providers.required"
                :placeholder="form.fields.allowed_providers.placeholder"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>

            <CadenceField
              :control-id="form.fields.excluded_providers.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.excluded_providers.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.excluded_providers.id"
                v-model="contactRequirement.excluded_providers"
                :name="form.fields.excluded_providers.name"
                :type="form.fields.excluded_providers.type"
                :required="form.fields.excluded_providers.required"
                :placeholder="form.fields.excluded_providers.placeholder"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>

            <CadenceField
              :control-id="form.fields.allowed_stations.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.allowed_stations.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.allowed_stations.id"
                v-model="contactRequirement.allowed_stations"
                :name="form.fields.allowed_stations.name"
                :type="form.fields.allowed_stations.type"
                :required="form.fields.allowed_stations.required"
                :placeholder="form.fields.allowed_stations.placeholder"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>

            <CadenceField
              :control-id="form.fields.excluded_stations.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.excluded_stations.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.excluded_stations.id"
                v-model="contactRequirement.excluded_stations"
                :name="form.fields.excluded_stations.name"
                :type="form.fields.excluded_stations.type"
                :required="form.fields.excluded_stations.required"
                :placeholder="form.fields.excluded_stations.placeholder"
                class="w-full input"
                @input="validate"
              />
            </CadenceField>
          </div>
        </CadenceDetailsFrame>

        <section :id="journey.rationale.id" class="border border-base-300 bg-base-200/20 p-5">
          <CadenceField
            :control-id="form.fields.rationale.id"
            wrapper-class="fieldset mb-3"
            :label="form.fields.rationale.label"
            label-class="hud-label block mb-1.5"
          >
            <textarea
              :id="form.fields.rationale.id"
              v-model="contactRequirement.rationale"
              :name="form.fields.rationale.name"
              :required="form.fields.rationale.required"
              :placeholder="form.fields.rationale.placeholder"
              :maxlength="form.fields.rationale.maxlength"
              class="w-full textarea"
              @input="validate"
            ></textarea>
          </CadenceField>
          <p v-if="activeError" :id="activeError.id" class="mt-2 text-sm text-error">
            {{ activeError.message }}
          </p>
          <div class="mt-4 flex justify-end gap-3">
            <a
              :id="actions.cancel.id"
              :href="actions.cancel.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-ghost btn-sm"
              >{{ actions.cancel.label }}</a
            >
            <button
              :id="actions.submit.id"
              type="submit"
              class="btn btn-primary btn-sm font-mono text-xs uppercase tracking-wider"
            >
              {{ actions.submit.label }}
            </button>
          </div>
        </section>
      </form>
    </div>
  </CadenceOpsViewport>
</template>
