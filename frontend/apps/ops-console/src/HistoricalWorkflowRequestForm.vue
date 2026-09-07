<script setup lang="ts">
import CadenceField from "@cadence/ui/CadenceField.vue";

type Attributes = Record<string, string>;

type TextPresentation = {
  class: string;
  text: string;
};

type OptionPresentation = {
  key: string;
  text: string;
  attrs: Attributes;
};

type FieldPresentation = {
  key: string;
  type: "text" | "select";
  wrapper_class: string;
  label: TextPresentation;
  control: {
    class: string;
    attrs: Attributes;
    options: OptionPresentation[];
  };
  errors: TextPresentation[];
};

type SectionPresentation = {
  class: string;
  title: TextPresentation;
  fields: FieldPresentation[];
};

type Presentation = {
  root: {
    id: string;
    class: string;
    attrs: Attributes;
  };
  hidden_fields: Array<{
    key: string;
    attrs: Attributes;
  }>;
  preview: {
    id: string;
    class: string;
    title: TextPresentation;
    list: {
      class: string;
      rows: Array<{
        key: string;
        class: string;
        attrs: Attributes;
        label: TextPresentation;
        value: TextPresentation & { attrs: Attributes };
      }>;
    };
  };
  request_context: SectionPresentation & {
    group: {
      class: string;
      fields: FieldPresentation[];
    };
  };
  source_window: SectionPresentation;
  confirmation: {
    id: string;
    class: string;
    field: {
      class: string;
      attrs: Attributes;
    };
    label: TextPresentation;
  };
  submit: {
    id: string;
    type: "submit";
    class: string;
    icon: {
      name: string;
      class: string;
    };
    text: string;
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <form
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <input v-for="field in presentation.hidden_fields" :key="field.key" v-bind="field.attrs" />

    <section :id="presentation.preview.id" :class="presentation.preview.class">
      <h3 :class="presentation.preview.title.class">{{ presentation.preview.title.text }}</h3>
      <dl :class="presentation.preview.list.class">
        <div
          v-for="row in presentation.preview.list.rows"
          :key="row.key"
          :class="row.class"
          v-bind="row.attrs"
        >
          <dt :class="row.label.class">{{ row.label.text }}</dt>
          <dd :class="row.value.class" v-bind="row.value.attrs">{{ row.value.text }}</dd>
        </div>
      </dl>
    </section>

    <section :class="presentation.request_context.class">
      <h3 :class="presentation.request_context.title.class">
        {{ presentation.request_context.title.text }}
      </h3>
      <CadenceField
        v-for="field in presentation.request_context.fields"
        :key="field.key"
        :wrapper-class="field.wrapper_class"
        :label="field.label.text"
        :label-class="field.label.class"
      >
        <select
          v-if="field.type === 'select'"
          :class="field.control.class"
          v-bind="field.control.attrs"
        >
          <option v-for="option in field.control.options" :key="option.key" v-bind="option.attrs">
            {{ option.text }}
          </option>
        </select>
        <input v-else :class="field.control.class" v-bind="field.control.attrs" />
        <template #errors>
          <p v-for="error in field.errors" :key="error.text" :class="error.class">
            {{ error.text }}
          </p>
        </template>
      </CadenceField>
      <div :class="presentation.request_context.group.class">
        <CadenceField
          v-for="field in presentation.request_context.group.fields"
          :key="field.key"
          :wrapper-class="field.wrapper_class"
          :label="field.label.text"
          :label-class="field.label.class"
        >
          <input :class="field.control.class" v-bind="field.control.attrs" />
          <template #errors>
            <p v-for="error in field.errors" :key="error.text" :class="error.class">
              {{ error.text }}
            </p>
          </template>
        </CadenceField>
      </div>
    </section>

    <section :class="presentation.source_window.class">
      <h3 :class="presentation.source_window.title.class">
        {{ presentation.source_window.title.text }}
      </h3>
      <CadenceField
        v-for="field in presentation.source_window.fields"
        :key="field.key"
        :wrapper-class="field.wrapper_class"
        :label="field.label.text"
        :label-class="field.label.class"
      >
        <input :class="field.control.class" v-bind="field.control.attrs" />
        <template #errors>
          <p v-for="error in field.errors" :key="error.text" :class="error.class">
            {{ error.text }}
          </p>
        </template>
      </CadenceField>
    </section>

    <label :id="presentation.confirmation.id" :class="presentation.confirmation.class">
      <input
        :class="presentation.confirmation.field.class"
        v-bind="presentation.confirmation.field.attrs"
      />
      <span :class="presentation.confirmation.label.class">
        {{ presentation.confirmation.label.text }}
      </span>
    </label>

    <button
      :id="presentation.submit.id"
      :type="presentation.submit.type"
      :class="presentation.submit.class"
    >
      <span :class="[presentation.submit.icon.name, presentation.submit.icon.class]"></span>
      {{ presentation.submit.text }}
    </button>
  </form>
</template>
