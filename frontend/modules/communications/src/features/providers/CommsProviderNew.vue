<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { reactive, watch } from "vue";
import CadenceNoticeFrame from "@cadence/ui/CadenceNoticeFrame.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceFormActions from "@cadence/ui/CadenceFormActions.vue";
import CadenceFormSectionHeader from "@cadence/ui/CadenceFormSectionHeader.vue";
import CadenceFormSectionFrame from "@cadence/ui/CadenceFormSectionFrame.vue";
import { providerFieldKeys } from "./provider-new.contracts";

import type {
  Page,
  Accounts,
  Notes,
  Section,
  Visibility,
  ProviderForm,
  ProviderFieldKey,
  ProviderValues,
  ProviderPayload,
} from "./provider-new.contracts";

const props = defineProps<{
  page: Page;
  accounts: Accounts;
  notes: Notes;
  form: ProviderForm;
  managedDraft?: boolean;
  canSave?: boolean;
}>();
useManagementHeader("/missions/:mission_id/comms/providers/new", () => ({
  description: props.page.subtitle,
}));

const emit = defineEmits<{
  validate: [payload: ProviderPayload];
  save: [payload: ProviderPayload];
}>();

const formValues = (form: ProviderForm): ProviderValues =>
  Object.fromEntries(
    providerFieldKeys.map((key) => [key, form.fields[key].value]),
  ) as ProviderValues;

const provider = reactive<ProviderValues>(formValues(props.form));
const pendingValidations: ProviderValues[] = [];
const supersededValidations: ProviderValues[] = [];
let acceptedServerValues = formValues(props.form);

const values = (): ProviderValues => ({ ...provider });

const sameValues = (left: ProviderValues, right: ProviderValues) =>
  providerFieldKeys.every((key) => left[key] === right[key]);

watch(
  () => props.form,
  (serverForm) => {
    const serverValues = formValues(serverForm);
    if (props.managedDraft) {
      Object.assign(provider, serverValues);
      acceptedServerValues = serverValues;
      return;
    }
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues),
    );

    if (acknowledgedIndex >= 0) {
      supersededValidations.push(...pendingValidations.slice(0, acknowledgedIndex));

      const hasNewerTyping = acknowledgedIndex < pendingValidations.length - 1;
      pendingValidations.splice(0, acknowledgedIndex + 1);
      acceptedServerValues = serverValues;

      if (!hasNewerTyping && sameValues(provider, serverValues)) {
        Object.assign(provider, serverValues);
      }

      return;
    }

    const supersededIndex = supersededValidations.findIndex((sent) =>
      sameValues(sent, serverValues),
    );

    if (supersededIndex >= 0) {
      supersededValidations.splice(supersededIndex, 1);
      return;
    }

    if (sameValues(serverValues, acceptedServerValues)) return;

    if (pendingValidations.length === 0 && sameValues(provider, acceptedServerValues)) {
      Object.assign(provider, serverValues);
      acceptedServerValues = serverValues;
    }
  },
  { deep: true },
);

const fieldsFor = (section: Section) => section.field_keys.map((key) => props.form.fields[key]);

const fieldsForKeys = (keys: ProviderFieldKey[]) => keys.map((key) => props.form.fields[key]);

const visible = (visibility: Visibility) => provider[visibility.field] === visibility.equals;

const validate = () => {
  const currentValues = values();
  if (!props.managedDraft) pendingValidations.push(currentValues);
  emit("validate", { provider: currentValues });
};

const save = () => emit("save", { provider: values() });
</script>

<template>
  <div :id="page.id" class="max-w-3xl space-y-6">
    <div
      v-if="accounts.empty"
      :id="accounts.empty_state.id"
      class="border border-warning/40 bg-warning/10 p-5"
    >
      <p class="font-semibold">{{ accounts.empty_state.heading }}</p>
      <p class="mt-1 text-sm text-base-content/70">{{ accounts.empty_state.message }}</p>
      <a
        :id="accounts.empty_state.action.id"
        :href="accounts.empty_state.action.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-secondary btn-sm mt-4"
        >{{ accounts.empty_state.action.label }}</a
      >
    </div>

    <form v-else :id="form.id" class="space-y-8" @submit.prevent="save">
      <CadenceFormSectionFrame :id="form.sections.binding.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.binding.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.binding.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          v-for="field in fieldsFor(form.sections.binding)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="field.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            v-if="field.type === 'select'"
            :id="field.id"
            v-model="provider[field.key]"
            :name="field.name"
            :required="field.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in field.options"
              :key="`${option.value}-${option.label}`"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
          <input
            v-else
            :id="field.id"
            v-model="provider[field.key]"
            :name="field.name"
            :type="field.type"
            :required="field.required"
            :placeholder="field.placeholder ?? undefined"
            :min="field.min ?? undefined"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>

        <div
          v-if="accounts.selected"
          :id="accounts.selected.id"
          class="border border-base-300 bg-base-200/60 p-4"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label">{{ accounts.selected.ownership_label }}</p>
              <p class="mt-1 font-medium">{{ accounts.selected.display_name }}</p>
              <p class="mt-1 font-mono text-xs text-base-content/50">
                {{ accounts.selected.version_label }}
              </p>
            </div>
            <span
              class="inline-flex rounded-full bg-success/20 px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide text-success"
              >{{ accounts.selected.badge.label }}</span
            >
          </div>
          <div class="mt-4 grid gap-3 sm:grid-cols-2">
            <div v-for="restriction in accounts.selected.restrictions" :key="restriction.label">
              <p class="hud-label">{{ restriction.label }}</p>
              <p class="mt-1 text-xs text-base-content/70">{{ restriction.summary }}</p>
            </div>
          </div>
          <p :id="notes.secret_boundary.id" class="mt-4 text-xs text-base-content/60">
            {{ notes.secret_boundary.text }}
          </p>
        </div>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.resource_scope.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.resource_scope.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.resource_scope.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          v-for="field in fieldsFor(form.sections.resource_scope)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="field.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="field.id"
            v-model="provider[field.key]"
            :name="field.name"
            :type="field.type"
            :required="field.required"
            :placeholder="field.placeholder ?? undefined"
            :min="field.min ?? undefined"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>
        <p :id="notes.resource_boundary.id" class="text-xs text-base-content/60">
          {{ notes.resource_boundary.text }}
        </p>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.delivery_policy.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.delivery_policy.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.delivery_policy.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.policy_mode.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.policy_mode.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.policy_mode.id"
            v-model="provider.policy_mode"
            :name="form.fields.policy_mode.name"
            :required="form.fields.policy_mode.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in form.fields.policy_mode.options"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>

        <CadenceNoticeFrame
          v-if="visible(form.conditional.approval_guidance.visible_when)"
          tone="info"
          :id="form.conditional.approval_guidance.id"
        >
          {{ form.conditional.approval_guidance.text }}
        </CadenceNoticeFrame>

        <div
          v-if="visible(form.conditional.bounded_policy.visible_when)"
          :id="form.conditional.bounded_policy.id"
          class="grid gap-4 sm:grid-cols-2"
        >
          <CadenceField
            v-for="field in fieldsForKeys(form.conditional.bounded_policy.field_keys)"
            :key="field.key"
            :control-id="field.id"
            wrapper-class="fieldset mb-3"
            :label="field.label"
            label-class="hud-label block mb-1.5"
          >
            <input
              :id="field.id"
              v-model="provider[field.key]"
              :name="field.name"
              :type="field.type"
              :required="field.required"
              :placeholder="field.placeholder ?? undefined"
              :min="field.min ?? undefined"
              class="w-full input"
              @input="validate"
            />
          </CadenceField>
        </div>

        <CadenceField
          :control-id="form.fields.deadline_behavior.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.deadline_behavior.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.deadline_behavior.id"
            v-model="provider.deadline_behavior"
            :name="form.fields.deadline_behavior.name"
            :required="form.fields.deadline_behavior.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in form.fields.deadline_behavior.options"
              :key="option.value"
              :value="option.value"
            >
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
          :disabled="managedDraft && !canSave"
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
