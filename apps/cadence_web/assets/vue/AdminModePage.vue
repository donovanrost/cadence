<script setup lang="ts">
type RawAttrs = Record<string, string>

type ElementPresentation = {
  attrs: RawAttrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type AdminModePresentation = {
  root: ElementPresentation
  header: {
    root: ElementPresentation
    brand: TextPresentation
    heading: TextPresentation
    body: TextPresentation
  }
  form: {
    attrs: RawAttrs
    hidden_fields: ElementPresentation[]
    password: {
      root: ElementPresentation
      label: TextPresentation
      input: ElementPresentation
    }
    submit: TextPresentation
  }
}

defineProps<{presentation: AdminModePresentation}>()
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <div v-bind="presentation.header.root.attrs">
      <p v-bind="presentation.header.brand.attrs">
        {{ presentation.header.brand.text }}
      </p>
      <h1 v-bind="presentation.header.heading.attrs">
        {{ presentation.header.heading.text }}
      </h1>
      <p v-bind="presentation.header.body.attrs">
        {{ presentation.header.body.text }}
      </p>
    </div>

    <form v-bind="presentation.form.attrs">
      <input
        v-for="field in presentation.form.hidden_fields"
        :key="field.attrs.name"
        v-bind="field.attrs"
      >

      <div v-bind="presentation.form.password.root.attrs">
        <label>
          <span v-bind="presentation.form.password.label.attrs">
            {{ presentation.form.password.label.text }}
          </span>
          <input v-bind="presentation.form.password.input.attrs">
        </label>
      </div>

      <button v-bind="presentation.form.submit.attrs">
        {{ presentation.form.submit.text }}
      </button>
    </form>
  </div>
</template>
