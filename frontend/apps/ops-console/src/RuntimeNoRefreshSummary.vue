<script setup lang="ts">
type Attributes = Record<string, string>

type Field = {
  key: string
  label: string
  label_class: string
  value: string
  value_class: string
  attributes: Attributes
}

type Summary = {
  section: {
    id: string
    class: string
    attributes: Attributes
  }
  heading: {
    class: string
    text: string
  }
  headline: {
    class: string
    text: string
  }
  fields: {
    class: string
    rows: Field[]
  }
  blocker: null | {
    id: string
    class: string
    rows: Field[]
  }
  admin_action: null | {
    href: string
    class: string
    attributes: Attributes
    icon: {
      class: string
      attributes: Attributes
    }
    label: string
  }
}

defineProps<{summary: Summary}>()
</script>

<template>
  <section
    :id="summary.section.id"
    :class="summary.section.class"
    v-bind="summary.section.attributes"
  >
    <h3 :class="summary.heading.class">{{ summary.heading.text }}</h3>
    <p :class="summary.headline.class">{{ summary.headline.text }}</p>
    <dl :class="summary.fields.class">
      <template v-for="field in summary.fields.rows" :key="field.key">
        <dt :class="field.label_class">{{ field.label }}</dt>
        <dd :class="field.value_class" v-bind="field.attributes">{{ field.value }}</dd>
      </template>
    </dl>
    <dl v-if="summary.blocker" :id="summary.blocker.id" :class="summary.blocker.class">
      <template v-for="field in summary.blocker.rows" :key="field.key">
        <dt :class="field.label_class">{{ field.label }}</dt>
        <dd :class="field.value_class" v-bind="field.attributes">{{ field.value }}</dd>
      </template>
    </dl>
    <a
      v-if="summary.admin_action"
      :href="summary.admin_action.href"
      :class="summary.admin_action.class"
      v-bind="summary.admin_action.attributes"
    >
      <span
        :class="summary.admin_action.icon.class"
        v-bind="summary.admin_action.icon.attributes"
      ></span>
      {{ summary.admin_action.label }}
    </a>
  </section>
</template>
