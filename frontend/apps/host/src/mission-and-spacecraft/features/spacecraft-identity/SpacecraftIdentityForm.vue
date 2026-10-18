<script setup lang="ts">
import { useManagementHeaders } from "@cadence/plugin-sdk/page-header";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import { computed, reactive } from "vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceFormActions from "@cadence/ui/CadenceFormActions.vue";
import CadenceNarrowFormPageFrame from "@cadence/ui/CadenceNarrowFormPageFrame.vue";
import CadenceFormSectionHeader from "@cadence/ui/CadenceFormSectionHeader.vue";
import CadenceFormSectionFrame from "@cadence/ui/CadenceFormSectionFrame.vue";

import type {
  IdentityData,
  IdentityErrors,
  SpacecraftPayload,
  SpacecraftValues,
} from "./contracts";
const props = withDefaults(
  defineProps<IdentityData & { disabled?: boolean; errors?: IdentityErrors }>(),
  { disabled: false, errors: () => ({}) },
);
const emit = defineEmits<{
  validate: [payload: SpacecraftPayload];
  save: [payload: SpacecraftPayload];
}>();
const spacecraft = reactive<SpacecraftValues>({
  display_name: props.form.fields.display_name.value,
  scid: props.form.fields.scid.value,
  spacecraft_type_id: props.form.fields.spacecraft_type_id.value,
  spacecraft_type_version: props.form.profile_version,
});
// A reconnect or validation reply must not replace an in-progress draft or its displayed version choices.
const options = props.profile_options.options;
const profileKey = (id: string, version: number | null) => JSON.stringify([id, version]);
const selection = computed({
  get: () => profileKey(spacecraft.spacecraft_type_id, spacecraft.spacecraft_type_version),
  set: (key) => {
    const selected = options.find((option) => profileKey(option.value, option.version) === key);
    if (selected) {
      spacecraft.spacecraft_type_id = selected.value;
      spacecraft.spacecraft_type_version = selected.version;
    }
  },
});
const profileErrors = computed(() => [
  ...(props.errors.spacecraft_type_id ?? []),
  ...(props.errors.spacecraft_type_version ?? []),
]);
function validate() {
  if (!props.disabled) emit("validate", { spacecraft: { ...spacecraft } });
}
function save() {
  if (!props.disabled) emit("save", { spacecraft: { ...spacecraft } });
}
const identityHeader = () => ({
  title: props.form.fields.display_name.value || props.page.heading,
  description: props.page.subtitle,
});
useManagementHeaders({
  "/missions/:mission_id/spacecraft/new": () => ({ description: props.page.subtitle }),
  "/missions/:mission_id/spacecraft/:spacecraft_id/identity": identityHeader,
  "/missions/:mission_id/spacecraft/:spacecraft_id/edit": identityHeader,
});
</script>

<template>
  <CadenceNarrowFormPageFrame :id="page.id">
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
            v-model="spacecraft.display_name"
            :name="form.fields.display_name.name"
            :type="form.fields.display_name.type"
            :required="form.fields.display_name.required"
            :disabled="disabled"
            :aria-invalid="errors.display_name?.length ? 'true' : undefined"
            :aria-describedby="
              errors.display_name?.length ? form.fields.display_name.id + '-errors' : undefined
            "
            class="w-full input"
            @input="validate"
          />
        </CadenceField>
        <div
          v-if="errors.display_name?.length"
          :id="form.fields.display_name.id + '-errors'"
          role="alert"
          class="text-sm text-error"
        >
          <p v-for="message in errors.display_name" :key="message">{{ message }}</p>
        </div>

        <CadenceField
          :control-id="form.fields.scid.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.scid.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.scid.id"
            v-model="spacecraft.scid"
            :name="form.fields.scid.name"
            :type="form.fields.scid.type"
            :required="form.fields.scid.required"
            :disabled="disabled"
            :aria-invalid="errors.scid?.length ? 'true' : undefined"
            :aria-describedby="errors.scid?.length ? form.fields.scid.id + '-errors' : undefined"
            class="w-full input"
            @input="validate"
          />
        </CadenceField>
        <div
          v-if="errors.scid?.length"
          :id="form.fields.scid.id + '-errors'"
          role="alert"
          class="text-sm text-error"
        >
          <p v-for="message in errors.scid" :key="message">{{ message }}</p>
        </div>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.profile.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.profile.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.profile.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <p v-if="form.configuration_href" class="text-sm text-base-content/70">
          Framing is managed in the spacecraft workspace.
          <CadenceLink
            id="spacecraft-identity-communications-link"
            :href="form.configuration_href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            >Configure communications</CadenceLink
          >.
        </p>
        <CadenceField
          v-else
          :control-id="form.fields.spacecraft_type_id.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.spacecraft_type_id.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.spacecraft_type_id.id"
            v-model="selection"
            :name="form.fields.spacecraft_type_id.name"
            :required="form.fields.spacecraft_type_id.required"
            :disabled="disabled"
            :aria-invalid="profileErrors.length ? 'true' : undefined"
            :aria-describedby="
              profileErrors.length ? form.fields.spacecraft_type_id.id + '-errors' : undefined
            "
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in options"
              :key="profileKey(option.value, option.version)"
              :value="profileKey(option.value, option.version)"
            >
              {{ option.label }}
            </option>
          </select>
        </CadenceField>
        <div
          v-if="profileErrors.length"
          :id="form.fields.spacecraft_type_id.id + '-errors'"
          role="alert"
          class="text-sm text-error"
        >
          <p v-for="message in profileErrors" :key="message">{{ message }}</p>
        </div>

        <p
          v-if="profile_options.empty && page.id === 'spacecraft-new-page'"
          class="text-xs text-base-content/70"
        >
          {{ profile_options.empty_state.message }}
          <a
            :id="profile_options.empty_state.action.id"
            :href="profile_options.empty_state.action.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
            >{{ profile_options.empty_state.action.label }}</a
          >
          {{ profile_options.empty_state.suffix }}
        </p>
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
  </CadenceNarrowFormPageFrame>
</template>
