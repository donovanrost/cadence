<script setup lang="ts">
import DashboardSectionList from "./DashboardSectionList.vue";

type Attributes = Record<string, string>;

type TextPresentation = {
  attrs: Attributes;
  text: string;
};

type StandardFieldPresentation = {
  wrapper: { attrs: Attributes };
  label: TextPresentation;
  control: { attrs: Attributes };
  errors: TextPresentation[];
};

type CheckboxFieldPresentation = {
  wrapper: { attrs: Attributes };
  label: { attrs: Attributes };
  hidden_control: { attrs: Attributes };
  control: { attrs: Attributes };
  text: {
    wrapper: { attrs: Attributes };
    label: TextPresentation;
  };
};

type Presentation = {
  root: { attrs: Attributes };
  section_list: Record<string, unknown>;
  form: {
    root: {
      attrs: Attributes;
      param: string;
      params: Record<string, string>;
    };
    section_id: { attrs: Attributes };
    heading: TextPresentation;
    title: StandardFieldPresentation;
    description: StandardFieldPresentation & {
      control: { attrs: Attributes; text: string };
    };
    collapsed_by_default: CheckboxFieldPresentation;
    error: TextPresentation | null;
    actions: {
      attrs: Attributes;
      save: TextPresentation;
      cancel: TextPresentation & { visible: boolean };
    };
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <DashboardSectionList :presentation="presentation.section_list" />

    <form v-bind="presentation.form.root.attrs">
      <input v-bind="presentation.form.section_id.attrs" />
      <p v-bind="presentation.form.heading.attrs">{{ presentation.form.heading.text }}</p>

      <div v-bind="presentation.form.title.wrapper.attrs">
        <label>
          <span v-bind="presentation.form.title.label.attrs">
            {{ presentation.form.title.label.text }}
          </span>
          <input v-bind="presentation.form.title.control.attrs" />
        </label>
        <p
          v-for="(error, index) in presentation.form.title.errors"
          :key="`title-error-${index}`"
          v-bind="error.attrs"
        >
          {{ error.text }}
        </p>
      </div>

      <div v-bind="presentation.form.description.wrapper.attrs">
        <label>
          <span v-bind="presentation.form.description.label.attrs">
            {{ presentation.form.description.label.text }}
          </span>
          <textarea v-bind="presentation.form.description.control.attrs">{{
            presentation.form.description.control.text
          }}</textarea>
        </label>
        <p
          v-for="(error, index) in presentation.form.description.errors"
          :key="`description-error-${index}`"
          v-bind="error.attrs"
        >
          {{ error.text }}
        </p>
      </div>

      <div v-bind="presentation.form.collapsed_by_default.wrapper.attrs">
        <label v-bind="presentation.form.collapsed_by_default.label.attrs">
          <input v-bind="presentation.form.collapsed_by_default.hidden_control.attrs" />
          <input v-bind="presentation.form.collapsed_by_default.control.attrs" />
          <span v-bind="presentation.form.collapsed_by_default.text.wrapper.attrs">
            <span v-bind="presentation.form.collapsed_by_default.text.label.attrs">
              {{ presentation.form.collapsed_by_default.text.label.text }}
            </span>
          </span>
        </label>
      </div>

      <p v-if="presentation.form.error" v-bind="presentation.form.error.attrs">
        {{ presentation.form.error.text }}
      </p>

      <div v-bind="presentation.form.actions.attrs">
        <button v-bind="presentation.form.actions.save.attrs">
          {{ presentation.form.actions.save.text }}
        </button>
        <button
          v-if="presentation.form.actions.cancel.visible"
          v-bind="presentation.form.actions.cancel.attrs"
        >
          {{ presentation.form.actions.cancel.text }}
        </button>
      </div>
    </form>
  </div>
</template>
