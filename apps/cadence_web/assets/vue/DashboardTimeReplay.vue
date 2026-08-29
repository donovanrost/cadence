<script setup lang="ts">
import CadenceField from "./ui/components/CadenceField.vue"

type AttrValue = string | boolean | null
type Attrs = Record<string, AttrValue>

type HiddenField = {
  wrapper_class: string
  attrs: Attrs
}

type SelectOption = {
  label: string
  value: string
  selected: boolean
  disabled: boolean
  title: string | null
}

type SelectField = {
  wrapper_class: string
  label: {
    class: string
    text: string
  }
  attrs: Attrs
  options: SelectOption[]
}

type Badge = {
  attrs: Attrs
  text: string
}

type WarningBadge = Badge & {
  icon_class: string
}

type ReplayPresentation = {
  root: {attrs: Attrs}
  heading: {
    attrs: Attrs
    text: string
  }
  body: {
    class: string
    form: {
      attrs: Attrs
      hidden_fields: HiddenField[]
      replay_run: SelectField
    }
    clock: Badge | null
  }
  warning: WarningBadge | null
}

defineProps<{presentation: ReplayPresentation}>()
</script>

<template>
  <section v-bind="presentation.root.attrs">
    <p v-bind="presentation.heading.attrs">{{ presentation.heading.text }}</p>
    <div :class="presentation.body.class">
      <form v-bind="presentation.body.form.attrs">
        <div
          v-for="field in presentation.body.form.hidden_fields"
          :key="String(field.attrs.id)"
          :class="field.wrapper_class"
        >
          <label>
            <input v-bind="field.attrs" />
          </label>
        </div>
          <CadenceField
            :wrapper-class="presentation.body.form.replay_run.wrapper_class"
            :label="presentation.body.form.replay_run.label.text"
            :label-class="presentation.body.form.replay_run.label.class"
          >
            <select v-bind="presentation.body.form.replay_run.attrs">
              <option
                v-for="(option, index) in presentation.body.form.replay_run.options"
                :key="`${option.value}-${index}`"
                :value="option.value"
                :selected="option.selected"
                :disabled="option.disabled"
                :title="option.title"
              >
                {{ option.label }}
              </option>
            </select>
          </CadenceField>
      </form>
      <span v-if="presentation.body.clock" v-bind="presentation.body.clock.attrs">
        {{ presentation.body.clock.text }}
      </span>
    </div>
    <span v-if="presentation.warning" v-bind="presentation.warning.attrs">
      <span :class="presentation.warning.icon_class"></span>
      {{ presentation.warning.text }}
    </span>
  </section>
</template>
