<script setup lang="ts">
type RawAttrs = Record<string, string>

type ElementPresentation = {
  attrs: RawAttrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type CardPresentation = {
  root: ElementPresentation
  body: ElementPresentation
  title: TextPresentation
  primary: TextPresentation
  detail: TextPresentation
}

type FieldPresentation = {
  root: ElementPresentation
  label: TextPresentation
  input: ElementPresentation
}

type InvitationFormPresentation = {
  attrs: RawAttrs
  hidden_fields: ElementPresentation[]
  fields: FieldPresentation[]
  actions: {
    root: ElementPresentation
    submit: TextPresentation
    help: TextPresentation
  }
}

type OrganizationInvitationPresentation = {
  root: ElementPresentation
  header: {
    root: ElementPresentation
    label: TextPresentation
    heading: TextPresentation
    body: TextPresentation
  }
  error: TextPresentation | null
  cards: {
    root: ElementPresentation
    items: CardPresentation[]
  }
  form: InvitationFormPresentation | null
}

defineProps<{presentation: OrganizationInvitationPresentation}>()
</script>

<template>
  <section v-bind="presentation.root.attrs">
    <div v-bind="presentation.header.root.attrs">
      <p v-bind="presentation.header.label.attrs">
        {{ presentation.header.label.text }}
      </p>
      <h1 v-bind="presentation.header.heading.attrs">
        {{ presentation.header.heading.text }}
      </h1>
      <p v-bind="presentation.header.body.attrs">
        {{ presentation.header.body.text }}
      </p>
    </div>

    <div v-if="presentation.error" v-bind="presentation.error.attrs">
      {{ presentation.error.text }}
    </div>

    <div v-bind="presentation.cards.root.attrs">
      <section
        v-for="card in presentation.cards.items"
        :key="card.title.text"
        v-bind="card.root.attrs"
      >
        <div v-bind="card.body.attrs">
          <p v-bind="card.title.attrs">{{ card.title.text }}</p>
          <p v-bind="card.primary.attrs">{{ card.primary.text }}</p>
          <p v-bind="card.detail.attrs">{{ card.detail.text }}</p>
        </div>
      </section>
    </div>

    <form v-if="presentation.form" v-bind="presentation.form.attrs">
      <input
        v-for="hiddenField in presentation.form.hidden_fields"
        :key="hiddenField.attrs.name"
        v-bind="hiddenField.attrs"
      >

      <div
        v-for="field in presentation.form.fields"
        :key="field.input.attrs.name"
        v-bind="field.root.attrs"
      >
        <label>
          <span v-bind="field.label.attrs">{{ field.label.text }}</span>
          <input v-bind="field.input.attrs">
        </label>
      </div>

      <div v-bind="presentation.form.actions.root.attrs">
        <button v-bind="presentation.form.actions.submit.attrs">
          {{ presentation.form.actions.submit.text }}
        </button>
        <p v-bind="presentation.form.actions.help.attrs">
          {{ presentation.form.actions.help.text }}
        </p>
      </div>
    </form>
  </section>
</template>
