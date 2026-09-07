<script setup lang="ts">
import CadenceField from "@cadence/ui/CadenceField.vue";

type AttrValue = string | boolean | null;
type Attrs = Record<string, AttrValue>;

type TextPresentation = {
  class: string;
  text: string;
};

type SelectOption = {
  label: string;
  value: string;
  selected: boolean;
  disabled: boolean;
  title: string | null;
};

type HiddenField = {
  wrapper_class: string;
  attrs: Attrs;
};

type SelectField = {
  wrapper_class: string;
  label: TextPresentation;
  attrs: Attrs;
  options: SelectOption[];
};

type Badge = {
  attrs: Attrs;
  icon_class: string;
  text: string;
};

type SelectSection = {
  attrs: Attrs;
  heading: {
    attrs: Attrs;
    text: string;
  };
  fields_class: string;
  fields: SelectField[];
  badge: Badge | null;
};

type MarkerField = {
  wrapper_class: string;
  label_class: string;
  false_input_attrs: Attrs;
  input_attrs: Attrs;
  label: TextPresentation;
};

type MarkerSection = {
  attrs: Attrs;
  heading: {
    attrs: Attrs;
    text: string;
    hidden_count: {
      attrs: Attrs;
      text: string;
    } | null;
  };
  toggles: {
    attrs: Attrs;
    fields: MarkerField[];
  };
};

type RuntimeControls = {
  root: { attrs: Attrs };
  header: {
    class: string;
    copy: {
      heading: TextPresentation;
      description: TextPresentation;
    };
    active_source: {
      attrs: Attrs;
      text: string;
    };
  };
  form: {
    attrs: Attrs;
    hidden_fields: HiddenField[];
    source: SelectSection;
    representation: SelectSection;
    semantics: SelectSection;
    markers: MarkerSection;
  };
};

defineProps<{ runtime_controls: RuntimeControls }>();
</script>

<template>
  <div v-bind="runtime_controls.root.attrs">
    <div data-dashboard-data-query-controls>
      <div :class="runtime_controls.header.class">
        <div>
          <p :class="runtime_controls.header.copy.heading.class">
            {{ runtime_controls.header.copy.heading.text }}
          </p>
          <p :class="runtime_controls.header.copy.description.class">
            {{ runtime_controls.header.copy.description.text }}
          </p>
        </div>
        <span v-bind="runtime_controls.header.active_source.attrs">
          {{ runtime_controls.header.active_source.text }}
        </span>
      </div>

      <form v-bind="runtime_controls.form.attrs">
        <div
          v-for="field in runtime_controls.form.hidden_fields"
          :key="String(field.attrs.id)"
          :class="field.wrapper_class"
        >
          <label>
            <input v-bind="field.attrs" />
          </label>
        </div>

        <section v-bind="runtime_controls.form.source.attrs">
          <p v-bind="runtime_controls.form.source.heading.attrs">
            {{ runtime_controls.form.source.heading.text }}
          </p>
          <div :class="runtime_controls.form.source.fields_class">
            <CadenceField
              v-for="field in runtime_controls.form.source.fields"
              :key="String(field.attrs.id)"
              :wrapper-class="field.wrapper_class"
              :label="field.label.text"
              :label-class="field.label.class"
            >
              <select v-bind="field.attrs">
                <option
                  v-for="option in field.options"
                  :key="option.value"
                  :value="option.value"
                  :selected="option.selected"
                  :disabled="option.disabled"
                  :title="option.title ?? undefined"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
          </div>
        </section>

        <section v-bind="runtime_controls.form.representation.attrs">
          <p v-bind="runtime_controls.form.representation.heading.attrs">
            {{ runtime_controls.form.representation.heading.text }}
          </p>
          <div :class="runtime_controls.form.representation.fields_class">
            <CadenceField
              v-for="field in runtime_controls.form.representation.fields"
              :key="String(field.attrs.id)"
              :wrapper-class="field.wrapper_class"
              :label="field.label.text"
              :label-class="field.label.class"
            >
              <select v-bind="field.attrs">
                <option
                  v-for="option in field.options"
                  :key="option.value"
                  :value="option.value"
                  :selected="option.selected"
                  :disabled="option.disabled"
                  :title="option.title ?? undefined"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
          </div>
        </section>

        <section v-bind="runtime_controls.form.semantics.attrs">
          <p v-bind="runtime_controls.form.semantics.heading.attrs">
            {{ runtime_controls.form.semantics.heading.text }}
          </p>
          <div :class="runtime_controls.form.semantics.fields_class">
            <CadenceField
              v-for="field in runtime_controls.form.semantics.fields"
              :key="String(field.attrs.id)"
              :wrapper-class="field.wrapper_class"
              :label="field.label.text"
              :label-class="field.label.class"
            >
              <select v-bind="field.attrs">
                <option
                  v-for="option in field.options"
                  :key="option.value"
                  :value="option.value"
                  :selected="option.selected"
                  :disabled="option.disabled"
                  :title="option.title ?? undefined"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
          </div>
          <span
            v-if="runtime_controls.form.semantics.badge"
            v-bind="runtime_controls.form.semantics.badge.attrs"
          >
            <span :class="runtime_controls.form.semantics.badge.icon_class"></span>
            {{ runtime_controls.form.semantics.badge.text }}
          </span>
        </section>

        <section v-bind="runtime_controls.form.markers.attrs">
          <p v-bind="runtime_controls.form.markers.heading.attrs">
            {{ runtime_controls.form.markers.heading.text }}
            <span
              v-if="runtime_controls.form.markers.heading.hidden_count"
              v-bind="runtime_controls.form.markers.heading.hidden_count.attrs"
            >
              {{ runtime_controls.form.markers.heading.hidden_count.text }}
            </span>
          </p>
          <div v-bind="runtime_controls.form.markers.toggles.attrs">
            <div
              v-for="field in runtime_controls.form.markers.toggles.fields"
              :key="String(field.input_attrs.id)"
              :class="field.wrapper_class"
            >
              <label :class="field.label_class">
                <input v-bind="field.false_input_attrs" />
                <input v-bind="field.input_attrs" />
                <span>
                  <span :class="field.label.class">{{ field.label.text }}</span>
                </span>
              </label>
            </div>
          </div>
        </section>
      </form>
    </div>
  </div>
</template>
