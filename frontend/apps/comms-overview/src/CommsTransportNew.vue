<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { computed, reactive, watch } from "vue";
import CadenceNoticeFrame from "@cadence/ui/CadenceNoticeFrame.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceFormActions from "@cadence/ui/CadenceFormActions.vue";
import CadenceFormSectionHeader from "@cadence/ui/CadenceFormSectionHeader.vue";
import CadenceFormSectionFrame from "@cadence/ui/CadenceFormSectionFrame.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type Page = {
  id: string;
  title: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
};

type Option = {
  label: string;
  value: string;
  disabled: boolean;
};

type Section = {
  id: string;
  number: string;
  title: string;
};

type FormValue = string | number | boolean;

type Field = {
  key: string;
  id: string;
  name: string;
  type: "hidden" | "text" | "number" | "select" | "checkbox";
  label: string;
  required: boolean;
  placeholder: string | null;
  options: Option[];
  value: string;
  provider_managed_id: string | null;
};

type Visibility = {
  field: string;
  equals: string;
} | null;

type ConfigurationField = {
  key: string;
  wrapper_id: string;
  id: string;
  name: string;
  type: "text" | "number" | "select" | "checkbox";
  label: string;
  required: boolean;
  placeholder: string | null;
  help: string | null;
  step: string | number | null;
  min: number | null;
  max: number | null;
  default: string;
  value: string;
  options: Option[];
  visible: boolean;
  visible_when: Visibility;
};

type ConfigurationSection = Section & {
  fields_id: string;
  description: string | null;
  fields: ConfigurationField[];
};

type DirectConfiguration = {
  id: string;
  kind: string;
  description: string | null;
  active: boolean;
  sections: ConfigurationSection[];
};

type Provider = {
  active: boolean;
  profile_fields_id: string;
  ready_count: number;
  selected: {
    display_name: string;
    version: number;
    status: "ready";
    status_label: string;
  } | null;
  empty_state: {
    id: string;
    visible: boolean;
    message: string;
    action: { label: string; href: string };
  };
  operator_summary: {
    id: string;
    label: string;
    text: string;
    endpoint: string;
  } | null;
  derivation_error: string | null;
};

type Detail = {
  label: string;
  value: string;
  mono: boolean;
};

type ProviderDerived = {
  active: boolean;
  id: string;
  number: string;
  title: string;
  description: string;
  configuration: {
    id: string;
    rows: Detail[];
    empty_text: string | null;
  };
};

type Review = {
  configuration_summary_id: string;
  ownership: { label: string; value: string; source: string };
  readiness: {
    label: string;
    status: "ready" | "attention";
    value: string;
    endpoint: string;
  };
  error: string | null;
  error_id: string;
  diagnostics: { id: string; label: string; json_id: string; json: string };
};

type TransportForm = {
  id: string;
  selected_origin: "direct" | "provider_managed";
  can_submit: boolean;
  sections: {
    identity: Section;
    origin: Section;
    source: Section;
    provider_capability: Section;
    review: Section;
  };
  fields: Record<string, Field>;
  origin_cards: { value: string; label: string; description: string }[];
  direct_configuration: DirectConfiguration;
  provider: Provider;
  provider_derived: ProviderDerived;
  review: Review;
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

type TransportValues = Record<string, string>;
type TransportPayload = { transport: TransportValues };

const props = defineProps<{
  page: Page;
  form: TransportForm;
}>();

const emit = defineEmits<{
  validate: [payload: TransportPayload];
  save: [payload: TransportPayload];
}>();

const configurationFields = (form: TransportForm) =>
  form.direct_configuration.sections.flatMap((section) => section.fields);

const formValues = (form: TransportForm): Record<string, FormValue> =>
  Object.fromEntries([
    ...Object.values(form.fields).map((field) => [field.key, field.value]),
    ...configurationFields(form).map((field) => [field.key, field.value]),
  ]);

const values = reactive<Record<string, FormValue>>(formValues(props.form));

const normalizedValue = (value: FormValue | undefined): string => {
  if (value === undefined || value === null) return "";
  return String(value);
};

const replaceValues = (serverValues: Record<string, FormValue>) => {
  for (const key of Object.keys(values)) {
    if (!(key in serverValues)) delete values[key];
  }

  Object.assign(values, serverValues);
};

watch(
  () => props.form,
  (serverForm) => {
    replaceValues(formValues(serverForm));
  },
  { deep: true },
);

const selectedOrigin = computed(() => normalizedValue(values.origin));

const visible = (field: ConfigurationField) =>
  field.visible_when === null ||
  normalizedValue(values[field.visible_when.field]) === field.visible_when.equals;

const transportValues = (
  fieldsOrigin = selectedOrigin.value,
  visibleConfigurationKeys: Set<string> | null = null,
): TransportValues => {
  const transport: TransportValues = {
    display_name: normalizedValue(values.display_name),
    origin: selectedOrigin.value,
    transport_kind: normalizedValue(values.transport_kind),
  };

  if (fieldsOrigin === "direct") {
    for (const field of configurationFields(props.form)) {
      const fieldVisible =
        visibleConfigurationKeys === null
          ? visible(field)
          : visibleConfigurationKeys.has(field.key);

      if (fieldVisible) transport[field.key] = normalizedValue(values[field.key]);
    }
  } else {
    transport.mission_provider_id = normalizedValue(values.mission_provider_id);
    transport.service_profile_id = normalizedValue(values.service_profile_id);
    transport.delivery_profile_id = normalizedValue(values.delivery_profile_id);
  }

  return transport;
};

const validate = (
  fieldsOrigin = selectedOrigin.value,
  visibleConfigurationKeys: Set<string> | null = null,
) => {
  const transport = transportValues(fieldsOrigin, visibleConfigurationKeys);
  emit("validate", { transport });
};

const save = () => emit("save", { transport: transportValues() });

const updateValue = (key: string, event: Event) => {
  values[key] = (event.target as HTMLInputElement | HTMLSelectElement).value;
  validate();
};

const updateOrigin = (event: Event) => {
  const previousOrigin = selectedOrigin.value;
  const visibleKeys = new Set(
    configurationFields(props.form)
      .filter(visible)
      .map((field) => field.key),
  );

  values.origin = (event.target as HTMLSelectElement).value;
  validate(previousOrigin, visibleKeys);
};

const updateConfigurationField = (field: ConfigurationField, event: Event) => {
  const visibleKeys = new Set(
    configurationFields(props.form)
      .filter(visible)
      .map((item) => item.key),
  );

  values[field.key] = (event.target as HTMLInputElement | HTMLSelectElement).value;
  validate(selectedOrigin.value, visibleKeys);
};

const updateCheckbox = (field: ConfigurationField, event: Event) => {
  const visibleKeys = new Set(
    configurationFields(props.form)
      .filter(visible)
      .map((item) => item.key),
  );

  values[field.key] = (event.target as HTMLInputElement).checked ? "true" : "false";
  validate(selectedOrigin.value, visibleKeys);
};

const statusClass = (status: "ready" | "attention") =>
  status === "ready" ? "bg-success/20 text-success" : "bg-warning/20 text-warning";
</script>

<template>
  <div :id="page.id" class="mx-auto max-w-4xl space-y-6">
    <CadencePageHeading :breadcrumbs="page.breadcrumbs">
      <template #title>{{ page.title }}</template>
      <template #description>{{ page.subtitle }}</template>
    </CadencePageHeading>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
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
            :value="normalizedValue(values.display_name)"
            :name="form.fields.display_name.name"
            :type="form.fields.display_name.type"
            :required="form.fields.display_name.required"
            class="w-full input"
            @input="updateValue('display_name', $event)"
          />
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.origin.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.origin.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.origin.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />
        <CadenceField
          :control-id="form.fields.origin.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.origin.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.origin.id"
            :value="normalizedValue(values.origin)"
            :name="form.fields.origin.name"
            :required="form.fields.origin.required"
            class="w-full select"
            @change="updateOrigin"
          >
            <option
              v-for="option in form.fields.origin.options"
              :key="option.value"
              :value="option.value"
              :disabled="option.disabled"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
        <div class="grid gap-3 md:grid-cols-2">
          <div
            v-for="card in form.origin_cards"
            :key="card.value"
            :class="[
              'border bg-base-200 p-4 transition-colors',
              selectedOrigin === card.value ? 'border-primary/60' : 'border-base-300',
            ]"
          >
            <p class="hud-label">{{ card.label }}</p>
            <p class="mt-2 text-sm text-base-content/65">{{ card.description }}</p>
          </div>
        </div>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.source.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.source.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.source.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          v-if="selectedOrigin === 'direct'"
          :control-id="form.fields.transport_kind.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.transport_kind.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.transport_kind.id"
            :value="normalizedValue(values.transport_kind)"
            :name="form.fields.transport_kind.name"
            :required="form.fields.transport_kind.required"
            class="w-full select"
            @change="updateValue('transport_kind', $event)"
          >
            <option
              v-for="option in form.fields.transport_kind.options"
              :key="option.value"
              :value="option.value"
              :disabled="option.disabled"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>

        <template v-else>
          <div class="fieldset mb-3">
            <label :for="form.fields.transport_kind.provider_managed_id ?? undefined">
              <input
                :id="form.fields.transport_kind.provider_managed_id ?? undefined"
                :name="form.fields.transport_kind.name"
                type="hidden"
                :value="normalizedValue(values.transport_kind)"
                class="w-full input"
              />
            </label>
          </div>
          <CadenceField
            :control-id="form.fields.mission_provider_id.id"
            wrapper-class="fieldset mb-3"
            :label="form.fields.mission_provider_id.label"
            label-class="hud-label block mb-1.5"
          >
            <select
              :id="form.fields.mission_provider_id.id"
              :value="normalizedValue(values.mission_provider_id)"
              :name="form.fields.mission_provider_id.name"
              :required="form.fields.mission_provider_id.required"
              class="w-full select"
              @change="updateValue('mission_provider_id', $event)"
            >
              <option value="">{{ form.fields.mission_provider_id.placeholder }}</option>
              <option
                v-for="option in form.fields.mission_provider_id.options"
                :key="option.value"
                :value="option.value"
                :disabled="option.disabled"
              >
                {{ option.label }}
              </option>
            </select>
          </CadenceField>
          <CadenceNoticeFrame
            v-if="form.provider.empty_state.visible"
            tone="warning"
            :id="form.provider.empty_state.id"
          >
            {{ form.provider.empty_state.message }}
            <a
              :href="form.provider.empty_state.action.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="ml-1 text-primary hover:underline"
              >{{ form.provider.empty_state.action.label }}</a
            >
          </CadenceNoticeFrame>
        </template>
      </CadenceFormSectionFrame>

      <div
        v-if="selectedOrigin === 'direct'"
        :id="form.direct_configuration.id"
        :data-extension-presentation="form.direct_configuration.kind"
        class="space-y-8"
      >
        <p v-if="form.direct_configuration.description" class="text-sm text-base-content/65">
          {{ form.direct_configuration.description }}
        </p>

        <CadenceFormSectionFrame
          v-for="section in form.direct_configuration.sections"
          :id="section.id"
          :key="section.id"
        >
          <CadenceFormSectionHeader
            wrapper-class="flex items-center gap-3"
            :number="section.number"
            number-class="hud-label text-primary/70"
            :title="section.title"
            title-class="hud-label"
            divider-class="flex-1 h-px bg-base-300/60"
          />
          <p v-if="section.description" class="text-sm text-base-content/65">
            {{ section.description }}
          </p>
          <div :id="section.fields_id" class="grid gap-x-4 sm:grid-cols-2">
            <template v-for="field in section.fields" :key="field.key">
              <div v-if="visible(field)" :id="field.wrapper_id">
                <div v-if="field.type === 'checkbox'" class="fieldset mb-3">
                  <label class="flex cursor-pointer items-start gap-3">
                    <input type="hidden" :name="field.name" value="false" />
                    <input
                      :id="field.id"
                      :name="field.name"
                      type="checkbox"
                      value="true"
                      :checked="normalizedValue(values[field.key]) === 'true'"
                      class="checkbox checkbox-sm mt-0.5"
                      @change="updateCheckbox(field, $event)"
                    />
                    <span>
                      <span class="block text-sm font-medium">{{ field.label }}</span>
                    </span>
                  </label>
                </div>
                <CadenceField
                  v-else
                  :control-id="field.id"
                  wrapper-class="fieldset mb-3"
                  :label="field.label"
                  label-class="hud-label block mb-1.5"
                >
                  <select
                    v-if="field.type === 'select'"
                    :id="field.id"
                    :value="normalizedValue(values[field.key])"
                    :name="field.name"
                    :required="field.required"
                    class="w-full select"
                    @change="updateConfigurationField(field, $event)"
                  >
                    <option
                      v-for="option in field.options"
                      :key="`${option.value}-${option.label}`"
                      :value="option.value"
                      :disabled="option.disabled"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                  <input
                    v-else
                    :id="field.id"
                    :value="normalizedValue(values[field.key])"
                    :name="field.name"
                    :type="field.type"
                    :placeholder="field.placeholder ?? undefined"
                    :required="field.required"
                    :step="field.step ?? undefined"
                    :min="field.min ?? undefined"
                    :max="field.max ?? undefined"
                    class="w-full input"
                    @input="updateConfigurationField(field, $event)"
                  />
                  <template v-if="field.help" #help>
                    <p class="-mt-1 mb-3 text-xs text-base-content/55">
                      {{ field.help }}
                    </p>
                  </template>
                </CadenceField>
              </div>
            </template>
          </div>
        </CadenceFormSectionFrame>
      </div>

      <template v-else>
        <CadenceFormSectionFrame :id="form.sections.provider_capability.id">
          <CadenceFormSectionHeader
            wrapper-class="flex items-center gap-3"
            :number="form.sections.provider_capability.number"
            number-class="hud-label text-primary/70"
            :title="form.sections.provider_capability.title"
            title-class="hud-label"
            divider-class="flex-1 h-px bg-base-300/60"
          />
          <div :id="form.provider.profile_fields_id" class="space-y-4">
            <div
              v-if="form.provider.selected"
              class="flex items-center justify-between border-l-2 border-success/60 bg-success/10 px-4 py-3"
            >
              <div>
                <p class="hud-label">Validated Provider</p>
                <p class="mt-1 text-sm">
                  {{ form.provider.selected.display_name }} · v{{ form.provider.selected.version }}
                </p>
              </div>
              <span
                class="inline-flex rounded-full bg-success/20 px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide text-success"
                >{{ form.provider.selected.status_label }}</span
              >
            </div>

            <CadenceField
              :control-id="form.fields.service_profile_id.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.service_profile_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="form.fields.service_profile_id.id"
                :value="normalizedValue(values.service_profile_id)"
                :name="form.fields.service_profile_id.name"
                :required="form.fields.service_profile_id.required"
                class="w-full select"
                @change="updateValue('service_profile_id', $event)"
              >
                <option value="">{{ form.fields.service_profile_id.placeholder }}</option>
                <option
                  v-for="option in form.fields.service_profile_id.options"
                  :key="option.value"
                  :value="option.value"
                  :disabled="option.disabled"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>

            <CadenceField
              :control-id="form.fields.delivery_profile_id.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.delivery_profile_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="form.fields.delivery_profile_id.id"
                :value="normalizedValue(values.delivery_profile_id)"
                :name="form.fields.delivery_profile_id.name"
                :required="form.fields.delivery_profile_id.required"
                class="w-full select"
                @change="updateValue('delivery_profile_id', $event)"
              >
                <option value="">{{ form.fields.delivery_profile_id.placeholder }}</option>
                <option
                  v-for="option in form.fields.delivery_profile_id.options"
                  :key="option.value"
                  :value="option.value"
                  :disabled="option.disabled"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>

            <div
              v-if="form.provider.operator_summary"
              :id="form.provider.operator_summary.id"
              class="border border-base-300 bg-base-200/70 p-4"
            >
              <p class="hud-label">{{ form.provider.operator_summary.label }}</p>
              <p class="mt-2 text-sm font-medium">{{ form.provider.operator_summary.text }}</p>
              <p class="mt-2 font-mono text-xs text-base-content/60">
                {{ form.provider.operator_summary.endpoint }}
              </p>
            </div>
            <CadenceNoticeFrame
              v-if="form.provider.derivation_error"
              tone="warning"
              id="transport-provider-derivation-error"
            >
              {{ form.provider.derivation_error }}
            </CadenceNoticeFrame>
          </div>
        </CadenceFormSectionFrame>

        <CadenceFormSectionFrame :id="form.provider_derived.id">
          <CadenceFormSectionHeader
            wrapper-class="flex items-center gap-3"
            :number="form.provider_derived.number"
            number-class="hud-label text-primary/70"
            :title="form.provider_derived.title"
            title-class="hud-label"
            divider-class="h-px flex-1 bg-base-300/60"
          />
          <p class="text-sm text-base-content/65">{{ form.provider_derived.description }}</p>
          <CadenceCard
            :id="form.provider_derived.configuration.id"
            class="card bg-base-200 border border-base-300"
            body-class="card-body p-6"
          >
            <div
              v-if="form.provider_derived.configuration.rows.length > 0"
              class="divide-y divide-base-300"
            >
              <CadenceDataRow
                v-for="row in form.provider_derived.configuration.rows"
                :key="row.label"
                row-class="hud-data-row"
                label-class="hud-data-label"
                :label="row.label"
              >
                <span :class="['hud-data-value', row.mono && 'font-mono text-sm']">
                  {{ row.value }}
                </span>
              </CadenceDataRow>
            </div>
            <p v-else class="text-sm text-base-content/60">
              {{ form.provider_derived.configuration.empty_text }}
            </p>
          </CadenceCard>
        </CadenceFormSectionFrame>
      </template>

      <CadenceFormSectionFrame :id="form.sections.review.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.review.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.review.title"
          title-class="hud-label"
          divider-class="h-px flex-1 bg-base-300/60"
        />

        <CadenceCard
          :id="form.review.configuration_summary_id"
          class="card bg-base-200 border border-base-300"
          body-class="card-body p-0"
        >
          <div class="grid divide-y divide-base-300 md:grid-cols-2 md:divide-x md:divide-y-0">
            <div class="p-5">
              <p class="hud-label">{{ form.review.ownership.label }}</p>
              <p class="mt-2 text-base font-semibold">{{ form.review.ownership.value }}</p>
              <p class="mt-1 text-sm text-base-content/60">
                {{ form.review.ownership.source }}
              </p>
            </div>
            <div class="p-5">
              <p class="hud-label">{{ form.review.readiness.label }}</p>
              <div class="mt-2">
                <span
                  :class="[
                    'inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide',
                    statusClass(form.review.readiness.status),
                  ]"
                  >{{ form.review.readiness.value }}</span
                >
              </div>
              <p class="mt-2 font-mono text-xs text-base-content/60">
                {{ form.review.readiness.endpoint }}
              </p>
            </div>
          </div>
        </CadenceCard>

        <p
          v-if="form.review.error"
          :id="form.review.error_id"
          class="border-l-2 border-error/70 bg-error/10 px-4 py-3 text-sm text-error"
        >
          {{ form.review.error }}
        </p>

        <CadenceDetailsFrame
          :id="form.review.diagnostics.id"
          class="rounded border border-base-300 bg-base-100/40 p-4 text-sm"
        >
          <summary class="cursor-pointer hud-label hover:text-primary">
            {{ form.review.diagnostics.label }}
          </summary>
          <pre
            :id="form.review.diagnostics.json_id"
            class="mt-3 max-h-96 overflow-auto font-mono text-xs text-base-content/70"
            >{{ form.review.diagnostics.json }}</pre>
        </CadenceDetailsFrame>
      </CadenceFormSectionFrame>

      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button
          :id="form.actions.submit.id"
          type="submit"
          class="btn btn-primary"
          :disabled="!form.can_submit"
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
  </div>
</template>
