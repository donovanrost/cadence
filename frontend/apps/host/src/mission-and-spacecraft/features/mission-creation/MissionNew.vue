<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { reactive, watch } from "vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceFormActions from "@cadence/ui/CadenceFormActions.vue";
import CadenceNarrowFormPageFrame from "@cadence/ui/CadenceNarrowFormPageFrame.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type MissionPage = {
  id: string;
  heading: string;
  breadcrumbs: Breadcrumb[];
};

type FormField = {
  id: string;
  name: string;
  type: "text";
  label: string;
  required: boolean;
  value: string;
};

type MissionForm = {
  id: string;
  fields: {
    display_name: FormField;
    slug: FormField;
  };
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

type MissionValues = {
  display_name: string;
  slug: string;
};

type MissionPayload = {
  mission: MissionValues;
};

const props = defineProps<{
  page: MissionPage;
  form: MissionForm;
  errors?: Record<string, string[]>;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  validate: [payload: MissionPayload];
  save: [payload: MissionPayload];
}>();

const values = reactive<MissionValues>({
  display_name: props.form.fields.display_name.value,
  slug: props.form.fields.slug.value,
});

watch(
  () => [props.form.fields.display_name.value, props.form.fields.slug.value] as const,
  ([displayName, slug], [previousDisplayName, previousSlug]) => {
    // Accept a server value only when no newer local edit has diverged from its prior prop.
    if (values.display_name === previousDisplayName) {
      values.display_name = displayName;
    }

    if (values.slug === previousSlug) {
      values.slug = slug;
    }
  },
);

const payload = (): MissionPayload => ({
  mission: {
    display_name: values.display_name,
    slug: values.slug,
  },
});

const validate = () => emit("validate", payload());
const save = () => {
  if (!props.disabled) emit("save", payload());
};
useManagementHeader("/missions/new", {});
</script>

<template>
  <CadenceNarrowFormPageFrame :id="page.id">
    <form :id="form.id" class="space-y-6" @submit.prevent="save">
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
          :disabled="disabled"
          :aria-invalid="!!errors?.display_name?.length"
          class="w-full input"
          @input="validate"
        />
        <template #errors
          ><p
            v-for="message in errors?.display_name"
            :key="message"
            role="alert"
            class="text-error text-sm"
          >
            {{ message }}
          </p></template
        >
      </CadenceField>

      <CadenceField
        :control-id="form.fields.slug.id"
        wrapper-class="fieldset mb-3"
        :label="form.fields.slug.label"
        label-class="hud-label block mb-1.5"
      >
        <input
          :id="form.fields.slug.id"
          v-model="values.slug"
          :name="form.fields.slug.name"
          :type="form.fields.slug.type"
          :required="form.fields.slug.required"
          :disabled="disabled"
          :aria-invalid="!!errors?.slug?.length"
          class="w-full input"
          @input="validate"
        />
        <template #errors
          ><p
            v-for="message in errors?.slug"
            :key="message"
            role="alert"
            class="text-error text-sm"
          >
            {{ message }}
          </p></template
        >
      </CadenceField>

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
