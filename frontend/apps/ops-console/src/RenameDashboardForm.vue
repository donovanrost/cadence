<script setup lang="ts">
type Attributes = Record<string, string>;

type TextFieldPresentation = {
  key: "name" | "description";
  wrapper: { attrs: Attributes };
  label: {
    attrs: Attributes;
    text: string;
  };
  control: {
    attrs: Attributes;
    value: string | null;
  };
};

type Presentation = {
  root: {
    attrs: Attributes;
    param: string;
    params: Record<string, string>;
  };
  fields: TextFieldPresentation[];
  submit: {
    attrs: Attributes;
    text: string;
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <form v-bind="presentation.root.attrs">
    <div v-for="field in presentation.fields" :key="field.key" v-bind="field.wrapper.attrs">
      <label>
        <span v-bind="field.label.attrs">{{ field.label.text }}</span>
        <input v-bind="field.control.attrs" :value="field.control.value" />
      </label>
    </div>
    <button v-bind="presentation.submit.attrs">{{ presentation.submit.text }}</button>
  </form>
</template>
