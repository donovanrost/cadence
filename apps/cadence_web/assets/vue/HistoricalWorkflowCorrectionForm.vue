<script setup lang="ts">
type Attributes = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}

type HiddenFieldPresentation = {
  id: string
  type: "hidden"
  name: string
  value: string | null
}

type TextFieldPresentation = {
  id: string
  name: string
  type: "text"
  value: string | null
  required: boolean
  wrapper_class: string
  label: TextPresentation
  input_class: string
  errors: string[]
  error_class: string
}

type Presentation = {
  root: {
    id: string
    class: string
    attrs: Attributes
  }
  hidden_fields: HiddenFieldPresentation[]
  header: {
    class: string
    heading: TextPresentation
    badge: TextPresentation
  }
  group_context: {
    visible: boolean
    id: string
    class: string
    attrs: Attributes
    rows: Array<{
      key: string
      label: TextPresentation
      value: TextPresentation
    }>
  }
  new_run: TextFieldPresentation
  source_fields: TextFieldPresentation[]
  source_fields_class: string
  confirmation: {
    row: {
      id: string
      class: string
    }
    input: {
      id: string
      type: "checkbox"
      name: string
      value: string
      required: boolean
      class: string
    }
    label: TextPresentation
  }
  submit: {
    id: string
    type: "submit"
    class: string
    icon: {
      name: string
      class: string
    }
    text: string
  }
}

defineProps<{presentation: Presentation}>()
</script>

<template>
  <form
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <input
      v-for="field in presentation.hidden_fields"
      :id="field.id"
      :key="field.id"
      :type="field.type"
      :name="field.name"
      :value="field.value"
    >

    <div :class="presentation.header.class">
      <h4 :class="presentation.header.heading.class">
        {{ presentation.header.heading.text }}
      </h4>
      <span :class="presentation.header.badge.class">{{ presentation.header.badge.text }}</span>
    </div>

    <dl
      v-if="presentation.group_context.visible"
      :id="presentation.group_context.id"
      :class="presentation.group_context.class"
      v-bind="presentation.group_context.attrs"
    >
      <template v-for="row in presentation.group_context.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class">{{ row.value.text }}</dd>
      </template>
    </dl>

    <div :class="presentation.new_run.wrapper_class">
      <label>
        <span :class="presentation.new_run.label.class">
          {{ presentation.new_run.label.text }}
        </span>
        <input
          :id="presentation.new_run.id"
          :name="presentation.new_run.name"
          :type="presentation.new_run.type"
          :value="presentation.new_run.value"
          :required="presentation.new_run.required"
          :class="presentation.new_run.input_class"
        >
      </label>
      <p
        v-for="(error, index) in presentation.new_run.errors"
        :key="`${presentation.new_run.id}-error-${index}`"
        :class="presentation.new_run.error_class"
      >
        {{ error }}
      </p>
    </div>

    <div :class="presentation.source_fields_class">
      <div
        v-for="field in presentation.source_fields"
        :key="field.id"
        :class="field.wrapper_class"
      >
        <label>
          <span :class="field.label.class">{{ field.label.text }}</span>
          <input
            :id="field.id"
            :name="field.name"
            :type="field.type"
            :value="field.value"
            :required="field.required"
            :class="field.input_class"
          >
        </label>
        <p
          v-for="(error, index) in field.errors"
          :key="`${field.id}-error-${index}`"
          :class="field.error_class"
        >
          {{ error }}
        </p>
      </div>
    </div>

    <label
      :id="presentation.confirmation.row.id"
      :class="presentation.confirmation.row.class"
    >
      <input
        :id="presentation.confirmation.input.id"
        :type="presentation.confirmation.input.type"
        :name="presentation.confirmation.input.name"
        :value="presentation.confirmation.input.value"
        :required="presentation.confirmation.input.required"
        :class="presentation.confirmation.input.class"
      >
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
