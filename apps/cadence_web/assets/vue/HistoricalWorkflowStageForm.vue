<script setup lang="ts">
import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"

type Attributes = Record<string, string>

type CompactInputPresentation = {
  wrapper_attrs: Attributes
  label: {
    attrs: Attributes
    text: string
  }
  input_attrs: Attributes
  errors: string[]
}

type Presentation = {
  root: {
    attrs: Attributes
  }
  hidden_fields: Array<{
    attrs: Attributes
  }>
  reason: CompactInputPresentation
  source_fields: {
    attrs: Attributes
    fields: CompactInputPresentation[]
  }
  confirmation: {
    attrs: Attributes
    input_attrs: Attributes
    label: {
      attrs: Attributes
      text: string
    }
  }
  actions: {
    attrs: Attributes
    items: Array<{
      attrs: Attributes
      icon: {
        attrs: Attributes
      }
      label: string
    }>
  }
}

defineProps<{presentation: Presentation}>()
</script>

<template>
  <form v-bind="presentation.root.attrs">
    <input
      v-for="field in presentation.hidden_fields"
      :key="field.attrs.id"
      v-bind="field.attrs"
    >

    <div v-bind="presentation.reason.wrapper_attrs">
      <label>
        <span v-bind="presentation.reason.label.attrs">
          {{ presentation.reason.label.text }}
        </span>
        <input v-bind="presentation.reason.input_attrs">
      </label>
      <CadenceValidationMessage
        v-for="(error, index) in presentation.reason.errors"
        :key="`reason-error-${index}`"
      >
        {{ error }}
      </CadenceValidationMessage>
    </div>

    <div v-bind="presentation.source_fields.attrs">
      <div
        v-for="field in presentation.source_fields.fields"
        :key="field.input_attrs.id"
        v-bind="field.wrapper_attrs"
      >
        <label>
          <span v-bind="field.label.attrs">{{ field.label.text }}</span>
          <input v-bind="field.input_attrs">
        </label>
        <CadenceValidationMessage
          v-for="(error, index) in field.errors"
          :key="`${field.input_attrs.id}-error-${index}`"
        >
          {{ error }}
        </CadenceValidationMessage>
      </div>
    </div>

    <label v-bind="presentation.confirmation.attrs">
      <input v-bind="presentation.confirmation.input_attrs">
      <span v-bind="presentation.confirmation.label.attrs">
        {{ presentation.confirmation.label.text }}
      </span>
    </label>

    <div v-bind="presentation.actions.attrs">
      <button
        v-for="action in presentation.actions.items"
        :key="action.attrs.id"
        v-bind="action.attrs"
      >
        <span v-bind="action.icon.attrs"></span> {{ action.label }}
      </button>
    </div>
  </form>
</template>
