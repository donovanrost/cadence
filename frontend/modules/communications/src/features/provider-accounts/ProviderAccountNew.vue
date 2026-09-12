<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { reactive, watch } from "vue";
import CadenceNoticeFrame from "@cadence/ui/CadenceNoticeFrame.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceFormActions from "@cadence/ui/CadenceFormActions.vue";
import CadenceFormSectionHeader from "@cadence/ui/CadenceFormSectionHeader.vue";
import CadenceFormSectionFrame from "@cadence/ui/CadenceFormSectionFrame.vue";

import type {
  Page,
  Option,
  BackendPresentation,
  Field,
  Section,
  ProviderAccountForm,
  ProviderAccountValues,
  ProviderAccountPayload,
} from "./registration.contracts";

const props = defineProps<{
  page: Page;
  form: ProviderAccountForm;
  managedDraft?: boolean;
  canSave?: boolean;
}>();

const emit = defineEmits<{
  validate: [payload: ProviderAccountPayload];
  save: [payload: ProviderAccountPayload];
}>();

const allFields = (form: ProviderAccountForm): Field[] => [
  ...Object.values(form.fields),
  ...form.connector.configuration.sections.flatMap((section) => section.fields),
];

const formValues = (form: ProviderAccountForm): ProviderAccountValues =>
  Object.fromEntries(allFields(form).map((field) => [field.key, field.value]));

const providerAccount = reactive<ProviderAccountValues>(formValues(props.form));
const pendingValidations: ProviderAccountValues[] = [];

const values = (): ProviderAccountValues =>
  Object.fromEntries(
    Object.entries(providerAccount).map(([key, value]) => [key, String(value ?? "")]),
  );

const acknowledges = (sent: ProviderAccountValues, server: ProviderAccountValues) =>
  Object.entries(sent).every(([key, value]) => !(key in server) || server[key] === value);

const replaceValues = (serverValues: ProviderAccountValues) => {
  for (const key of Object.keys(providerAccount)) {
    if (!(key in serverValues)) delete providerAccount[key];
  }

  Object.assign(providerAccount, serverValues);
};

const optionIncludes = (options: Option[], value: string | undefined) =>
  options.some((option) => option.value === value && !option.disabled);

watch(
  () => props.form,
  (serverForm) => {
    const serverValues = formValues(serverForm);
    if (props.managedDraft) {
      replaceValues(serverValues);
      return;
    }
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      acknowledges(sent, serverValues),
    );
    const latestPending = pendingValidations[pendingValidations.length - 1];
    const hasNewerTyping =
      acknowledgedIndex >= 0
        ? acknowledgedIndex < pendingValidations.length - 1
        : latestPending !== undefined && !acknowledges(latestPending, serverValues);
    const serverCorrectedSelection =
      (latestPending !== undefined &&
        !optionIncludes(serverForm.connector.options, latestPending.provider_type)) ||
      (latestPending !== undefined &&
        !optionIncludes(serverForm.fields.backend_type.options, latestPending.backend_type));

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1);

    if (!hasNewerTyping || serverCorrectedSelection) {
      if (serverCorrectedSelection) pendingValidations.splice(0);
      replaceValues(serverValues);
    }
  },
  { deep: true },
);

const fieldsFor = (section: Section) =>
  section.field_keys.map((key) => props.form.fields[key]).filter((field) => field !== undefined);

const visible = (field: Field) =>
  field.visible_when === undefined ||
  field.visible_when === null ||
  (providerAccount[field.visible_when.field] ?? "") === field.visible_when.equals;

const presentation = (field: Field): BackendPresentation | undefined =>
  field.presentations?.[providerAccount.backend_type ?? ""];

const fieldLabel = (field: Field) => presentation(field)?.label ?? field.label ?? "";
const fieldPlaceholder = (field: Field) =>
  presentation(field)?.placeholder ?? field.placeholder ?? undefined;

const validate = () => {
  const currentValues = values();
  if (!props.managedDraft) pendingValidations.push(currentValues);
  emit("validate", { provider_account: currentValues });
};

const save = () => emit("save", { provider_account: values() });
</script>

<template>
  <div :id="page.id" class="max-w-3xl space-y-6">
    <CadencePageHeading :breadcrumbs="page.breadcrumbs">
      <template #title>{{ page.heading }}</template>
      <template #description>{{ page.subtitle }}</template>
    </CadencePageHeading>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <input
        v-for="fieldKey in form.hidden_field_keys"
        :id="form.fields[fieldKey].id"
        :key="fieldKey"
        :name="form.fields[fieldKey].name"
        type="hidden"
        :value="providerAccount[fieldKey]"
      />

      <CadenceFormSectionFrame :id="form.sections.network_identity.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.network_identity.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.network_identity.title"
          title-class="hud-label"
          divider-class="h-px flex-1 bg-base-300/60"
        />

        <CadenceField
          v-for="field in fieldsFor(form.sections.network_identity)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="fieldLabel(field)"
          label-class="hud-label mb-1.5 block"
        >
          <select
            v-if="field.type === 'select'"
            :id="field.id"
            v-model="providerAccount[field.key]"
            :name="field.name"
            :required="field.required"
            class="select w-full"
            @change="validate"
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
            v-model="providerAccount[field.key]"
            :name="field.name"
            :type="field.type"
            :placeholder="fieldPlaceholder(field)"
            :required="field.required"
            :min="field.min ?? undefined"
            :max="field.max ?? undefined"
            :step="field.step ?? undefined"
            class="input w-full"
            @input="validate"
          />
        </CadenceField>

        <div
          :id="form.connector.selected.id"
          :data-provider-type="form.connector.selected.form_value"
          :data-provider-client="form.connector.selected.client_key"
          class="grid grid-cols-[0.3rem_minmax(0,1fr)_auto] gap-4 border-y border-base-300/70 bg-base-200/45 px-4 py-3"
        >
          <span class="rounded-full bg-info"></span>
          <div>
            <p class="hud-label">Compiled Provider Connector</p>
            <p class="mt-1 font-medium">{{ form.connector.selected.label }}</p>
            <p class="mt-1 text-xs text-base-content/60">
              {{ form.connector.selected.description }}
            </p>
          </div>
          <span
            class="self-start font-mono text-[0.65rem] uppercase tracking-[0.12em] text-base-content/45"
            >{{ form.connector.selected.client_key }}</span
          >
        </div>

        <CadenceNoticeFrame tone="info" :id="form.connector.boundary.id">
          {{ form.connector.boundary.text }}
        </CadenceNoticeFrame>
      </CadenceFormSectionFrame>

      <div
        :id="form.connector.configuration.id"
        :data-extension-presentation="form.connector.configuration.kind"
        class="space-y-8"
      >
        <p v-if="form.connector.configuration.description" class="text-sm text-base-content/65">
          {{ form.connector.configuration.description }}
        </p>

        <CadenceFormSectionFrame
          v-for="section in form.connector.configuration.sections"
          :id="section.id"
          :key="section.id"
        >
          <CadenceFormSectionHeader
            wrapper-class="flex items-center gap-3"
            :number="section.number"
            number-class="hud-label text-primary/70"
            :title="section.title"
            title-class="hud-label"
            divider-class="h-px flex-1 bg-base-300/60"
          />

          <p v-if="section.description" class="text-sm text-base-content/65">
            {{ section.description }}
          </p>

          <div :id="section.fields_id" class="grid gap-x-4 sm:grid-cols-2">
            <template v-for="field in section.fields" :key="field.key">
              <CadenceField
                v-if="visible(field)"
                :id="field.wrapper_id"
                :control-id="field.id"
                wrapper-class="fieldset mb-3"
                :label="fieldLabel(field)"
                label-class="hud-label mb-1.5 block"
              >
                <select
                  v-if="field.type === 'select'"
                  :id="field.id"
                  v-model="providerAccount[field.key]"
                  :name="field.name"
                  :required="field.required"
                  class="select w-full"
                  @change="validate"
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
                <textarea
                  v-else-if="field.type === 'textarea'"
                  :id="field.id"
                  v-model="providerAccount[field.key]"
                  :name="field.name"
                  :placeholder="fieldPlaceholder(field)"
                  :required="field.required"
                  class="textarea w-full"
                  @input="validate"
                ></textarea>
                <input
                  v-else
                  :id="field.id"
                  v-model="providerAccount[field.key]"
                  :name="field.name"
                  :type="field.type"
                  :placeholder="fieldPlaceholder(field)"
                  :required="field.required"
                  :min="field.min ?? undefined"
                  :max="field.max ?? undefined"
                  :step="field.step ?? undefined"
                  class="input w-full"
                  @input="validate"
                />
                <template #help>
                  <p v-if="field.help" class="-mt-1 mb-3 text-xs text-base-content/55">
                    {{ field.help }}
                  </p>
                </template>
              </CadenceField>
            </template>
          </div>
        </CadenceFormSectionFrame>
      </div>

      <CadenceFormSectionFrame :id="form.sections.credential_registry.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.credential_registry.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.credential_registry.title"
          title-class="hud-label"
          divider-class="h-px flex-1 bg-base-300/60"
        />

        <CadenceField
          v-for="field in fieldsFor(form.sections.credential_registry)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="fieldLabel(field)"
          label-class="hud-label mb-1.5 block"
        >
          <select
            v-if="field.type === 'select'"
            :id="field.id"
            v-model="providerAccount[field.key]"
            :name="field.name"
            :required="field.required"
            class="select w-full"
            @change="validate"
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
            v-model="providerAccount[field.key]"
            :name="field.name"
            :type="field.type"
            :placeholder="fieldPlaceholder(field)"
            :required="field.required"
            :min="field.min ?? undefined"
            :max="field.max ?? undefined"
            :step="field.step ?? undefined"
            class="input w-full"
            @input="validate"
          />
        </CadenceField>

        <p :id="form.credential_note.id" class="text-xs text-base-content/60">
          {{ form.credential_note.text }}
        </p>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.organization_guardrails.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.organization_guardrails.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.organization_guardrails.title"
          title-class="hud-label"
          divider-class="h-px flex-1 bg-base-300/60"
        />

        <CadenceField
          v-for="field in fieldsFor(form.sections.organization_guardrails)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="fieldLabel(field)"
          label-class="hud-label mb-1.5 block"
        >
          <input
            :id="field.id"
            v-model="providerAccount[field.key]"
            :name="field.name"
            :type="field.type"
            :placeholder="fieldPlaceholder(field)"
            :required="field.required"
            :min="field.min ?? undefined"
            :max="field.max ?? undefined"
            :step="field.step ?? undefined"
            class="input w-full"
            @input="validate"
          />
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button
          :id="form.actions.submit.id"
          type="submit"
          class="btn btn-primary"
          :disabled="canSave === false"
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
