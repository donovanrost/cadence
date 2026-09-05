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

type EvidenceField = Field & {
  visible: boolean
}

type EvidenceItem = {
  key: number
  attributes: Attributes
  button: {
    type: "button"
    class: string
    attributes: Attributes
  }
  fields: EvidenceField[]
}

type HiddenEvidence = {
  visible: false
}

type VisibleEvidence = {
  visible: true
  section: {
    id: string
    class: string
    attributes: Attributes
  }
  heading: {
    class: string
    text: string
  }
  states: {
    class: string
    rows: Field[]
  }
  list: {
    class: string
    items: EvidenceItem[]
  }
}

type Presentation = {
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
  evidence: HiddenEvidence | VisibleEvidence
}

defineProps<{presentation: Presentation}>()
</script>

<template>
  <section
    :id="presentation.section.id"
    :class="presentation.section.class"
    v-bind="presentation.section.attributes"
  >
    <h3 :class="presentation.heading.class">{{ presentation.heading.text }}</h3>
    <p :class="presentation.headline.class">{{ presentation.headline.text }}</p>
    <dl :class="presentation.fields.class">
      <template v-for="field in presentation.fields.rows" :key="field.key">
        <dt :class="field.label_class">{{ field.label }}</dt>
        <dd :class="field.value_class" v-bind="field.attributes">{{ field.value }}</dd>
      </template>
    </dl>
    <div
      v-if="presentation.evidence.visible"
      :id="presentation.evidence.section.id"
      :class="presentation.evidence.section.class"
      v-bind="presentation.evidence.section.attributes"
    >
      <h4 :class="presentation.evidence.heading.class">
        {{ presentation.evidence.heading.text }}
      </h4>
      <dl :class="presentation.evidence.states.class">
        <div v-for="state in presentation.evidence.states.rows" :key="state.key">
          <dt :class="state.label_class">{{ state.label }}</dt>
          <dd :class="state.value_class" v-bind="state.attributes">{{ state.value }}</dd>
        </div>
      </dl>
      <ul :class="presentation.evidence.list.class">
        <li
          v-for="item in presentation.evidence.list.items"
          :key="item.key"
          v-bind="item.attributes"
        >
          <button
            :type="item.button.type"
            :class="item.button.class"
            v-bind="item.button.attributes"
          >
            <template v-for="field in item.fields" :key="field.key">
              <template v-if="field.visible">
                <span :class="field.label_class">{{ field.label }}</span>
                <span :class="field.value_class" v-bind="field.attributes">
                  {{ field.value }}
                </span>
              </template>
            </template>
          </button>
        </li>
      </ul>
    </div>
  </section>
</template>
