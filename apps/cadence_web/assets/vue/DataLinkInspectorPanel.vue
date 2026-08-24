<script setup lang="ts">
import ClipboardButton from "./ClipboardButton.vue"

type AttrValue = string | number | boolean | null
type Attrs = Record<string, AttrValue>

type TextPresentation = {
  class: string
  text: string
}

type Row = {
  key: string
  label: TextPresentation
  value: TextPresentation & {attrs: Attrs}
}

type RowSection = {
  attrs: Attrs
  heading: TextPresentation
  list_class: string
  rows: Row[]
}

type Outcome = {
  attrs: Attrs
  message: string | null
}

type Option = {
  label: string
  value: string
  selected: boolean
  disabled: boolean
  title: string | null
}

type FormField = {
  wrapper_class: string
  label: TextPresentation
  attrs: Attrs
  options?: Option[]
}

type FormPresentation = {
  attrs: Attrs
  hidden_fields: Attrs[]
  fields: FormField[]
  confirmation: {
    row: {attrs: Attrs}
    input: {attrs: Attrs}
    label: TextPresentation
  }
  submit: {
    attrs: Attrs
    icon_class: string
    text: string
  }
}

type Effect = {
  attrs: Attrs
  label: TextPresentation
  summary: {attrs: Attrs; text: string}
}

type WorkflowExplanation = {
  attrs: Attrs
  header: {
    class: string
    heading: TextPresentation
    badge: TextPresentation
  }
  summary: {attrs: Attrs; text: string}
  list_class: string
  rows: Row[]
}

type RevisionDecision = {
  attrs: Attrs
  action_outcome: Outcome | null
  header: {
    class: string
    heading: TextPresentation
    badge: TextPresentation
  }
  form: FormPresentation
  effects: Effect[]
}

type LateDataPolicy = {
  attrs: Attrs
  header: {
    class: string
    heading: TextPresentation
    badges_class: string
    lifecycle_badge: TextPresentation
    execution_badge: TextPresentation
  }
  action_outcome: Outcome | null
  form: FormPresentation
  effects: Effect[]
}

type NavigationEntry = {
  attrs: Attrs
  from: string
  via: string
}

type RelatedLink = {
  attrs: Attrs
  target: string
  target_id: string
  label: string
}

type Presentation = {
  root: {attrs: Attrs}
  header: {
    class: string
    badges_class: string
    target: TextPresentation
    status: TextPresentation
    message: TextPresentation | null
  }
  clipboard: {
    button_id: string
    clipboard_text: string
    button_class: string
    icon: string
    icon_class: string
    label: string
  }
  actions: Array<{
    attrs: Attrs
    icon_class: string
    label: string
  }>
  action_outcome: Outcome | null
  selection: RowSection | null
  workflow_explanation: WorkflowExplanation | null
  revision_decision: RevisionDecision | null
  late_data_policy: LateDataPolicy | null
  historical_workflow_navigation: {
    attrs: Attrs
    icon_class: string
    text: string
  } | null
  navigation: {
    attrs: Attrs
    heading: TextPresentation
    entries: NavigationEntry[]
  } | null
  record: RowSection | null
  related: {
    attrs: Attrs
    heading: TextPresentation
    groups_class: string
    groups: Array<{
      attrs: Attrs
      header_class: string
      heading: TextPresentation
      count: TextPresentation
      links: RelatedLink[]
    }>
  } | null
  runtime_context: RowSection | null
}

defineProps<{presentation: Presentation}>()
</script>

<template>
  <div :class="presentation.header.class">
    <div :class="presentation.header.badges_class">
      <span :class="presentation.header.target.class">{{ presentation.header.target.text }}</span>
      <span :class="presentation.header.status.class">{{ presentation.header.status.text }}</span>
    </div>
    <p v-if="presentation.header.message" :class="presentation.header.message.class">
      {{ presentation.header.message.text }}
    </p>
  </div>

  <ClipboardButton v-bind="presentation.clipboard" />

  <a v-for="action in presentation.actions" :key="String(action.attrs.id)" v-bind="action.attrs">
    <span :class="action.icon_class"></span>
    {{ action.label }}
  </a>

  <div v-if="presentation.action_outcome" v-bind="presentation.action_outcome.attrs">
    {{ presentation.action_outcome.message }}
  </div>

  <section v-if="presentation.selection" v-bind="presentation.selection.attrs">
    <h3 :class="presentation.selection.heading.class">{{ presentation.selection.heading.text }}</h3>
    <dl :class="presentation.selection.list_class">
      <template v-for="row in presentation.selection.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class" v-bind="row.value.attrs">{{ row.value.text }}</dd>
      </template>
    </dl>
  </section>

  <section
    v-if="presentation.workflow_explanation"
    v-bind="presentation.workflow_explanation.attrs"
  >
    <div :class="presentation.workflow_explanation.header.class">
      <h3 :class="presentation.workflow_explanation.header.heading.class">
        {{ presentation.workflow_explanation.header.heading.text }}
      </h3>
      <span :class="presentation.workflow_explanation.header.badge.class">
        {{ presentation.workflow_explanation.header.badge.text }}
      </span>
    </div>
    <p v-bind="presentation.workflow_explanation.summary.attrs">
      {{ presentation.workflow_explanation.summary.text }}
    </p>
    <dl :class="presentation.workflow_explanation.list_class">
      <template v-for="row in presentation.workflow_explanation.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class" v-bind="row.value.attrs">{{ row.value.text }}</dd>
      </template>
    </dl>
  </section>

  <section v-if="presentation.revision_decision" v-bind="presentation.revision_decision.attrs">
    <div
      v-if="presentation.revision_decision.action_outcome"
      v-bind="presentation.revision_decision.action_outcome.attrs"
    >
      {{ presentation.revision_decision.action_outcome.message }}
    </div>
    <div :class="presentation.revision_decision.header.class">
      <h3 :class="presentation.revision_decision.header.heading.class">
        {{ presentation.revision_decision.header.heading.text }}
      </h3>
      <span :class="presentation.revision_decision.header.badge.class">
        {{ presentation.revision_decision.header.badge.text }}
      </span>
    </div>
    <form v-bind="presentation.revision_decision.form.attrs">
      <input
        v-for="field in presentation.revision_decision.form.hidden_fields"
        :key="String(field.id)"
        v-bind="field"
      >
      <div
        id="dashboard-revision-decision-effect-preview"
        class="grid grid-cols-1 gap-1 text-[0.68rem] sm:grid-cols-2"
      >
        <div
          v-for="effect in presentation.revision_decision.effects"
          :key="String(effect.attrs['data-revision-decision-effect'])"
          v-bind="effect.attrs"
        >
          <div :class="effect.label.class">{{ effect.label.text }}</div>
          <div v-bind="effect.summary.attrs">{{ effect.summary.text }}</div>
        </div>
      </div>
      <div class="grid grid-cols-1 gap-2">
        <div
          v-for="field in presentation.revision_decision.form.fields"
          :key="String(field.attrs.id)"
          :class="field.wrapper_class"
        >
          <label>
            <span :class="field.label.class">{{ field.label.text }}</span>
            <select v-if="field.options" v-bind="field.attrs">
              <option
                v-for="option in field.options"
                :key="option.value"
                :value="option.value"
                :selected="option.selected"
                :disabled="option.disabled"
                :title="option.title"
              >
                {{ option.label }}
              </option>
            </select>
            <input v-else v-bind="field.attrs">
          </label>
        </div>
      </div>
      <label v-bind="presentation.revision_decision.form.confirmation.row.attrs">
        <input v-bind="presentation.revision_decision.form.confirmation.input.attrs">
        <span :class="presentation.revision_decision.form.confirmation.label.class">
          {{ presentation.revision_decision.form.confirmation.label.text }}
        </span>
      </label>
      <button v-bind="presentation.revision_decision.form.submit.attrs">
        <span :class="presentation.revision_decision.form.submit.icon_class"></span>
        {{ presentation.revision_decision.form.submit.text }}
      </button>
    </form>
  </section>

  <section v-if="presentation.late_data_policy" v-bind="presentation.late_data_policy.attrs">
    <div :class="presentation.late_data_policy.header.class">
      <h3 :class="presentation.late_data_policy.header.heading.class">
        {{ presentation.late_data_policy.header.heading.text }}
      </h3>
      <div :class="presentation.late_data_policy.header.badges_class">
        <span :class="presentation.late_data_policy.header.lifecycle_badge.class">
          {{ presentation.late_data_policy.header.lifecycle_badge.text }}
        </span>
        <span :class="presentation.late_data_policy.header.execution_badge.class">
          {{ presentation.late_data_policy.header.execution_badge.text }}
        </span>
      </div>
    </div>
    <div
      v-if="presentation.late_data_policy.action_outcome"
      v-bind="presentation.late_data_policy.action_outcome.attrs"
    >
      {{ presentation.late_data_policy.action_outcome.message }}
    </div>
    <form v-bind="presentation.late_data_policy.form.attrs">
      <input
        v-for="field in presentation.late_data_policy.form.hidden_fields"
        :key="String(field.id)"
        v-bind="field"
      >
      <div
        id="dashboard-late-data-policy-effect-preview"
        class="grid grid-cols-1 gap-1 text-[0.68rem] sm:grid-cols-2"
      >
        <div
          v-for="effect in presentation.late_data_policy.effects"
          :key="String(effect.attrs['data-late-data-policy-effect'])"
          v-bind="effect.attrs"
        >
          <div :class="effect.label.class">{{ effect.label.text }}</div>
          <div v-bind="effect.summary.attrs">{{ effect.summary.text }}</div>
        </div>
      </div>
      <div class="grid grid-cols-1 gap-2">
        <div
          v-for="field in presentation.late_data_policy.form.fields"
          :key="String(field.attrs.id)"
          :class="field.wrapper_class"
        >
          <label>
            <span :class="field.label.class">{{ field.label.text }}</span>
            <select v-if="field.options" v-bind="field.attrs">
              <option
                v-for="option in field.options"
                :key="option.value"
                :value="option.value"
                :selected="option.selected"
                :disabled="option.disabled"
                :title="option.title"
              >
                {{ option.label }}
              </option>
            </select>
            <input v-else v-bind="field.attrs">
          </label>
        </div>
      </div>
      <label v-bind="presentation.late_data_policy.form.confirmation.row.attrs">
        <input v-bind="presentation.late_data_policy.form.confirmation.input.attrs">
        <span :class="presentation.late_data_policy.form.confirmation.label.class">
          {{ presentation.late_data_policy.form.confirmation.label.text }}
        </span>
      </label>
      <button v-bind="presentation.late_data_policy.form.submit.attrs">
        <span :class="presentation.late_data_policy.form.submit.icon_class"></span>
        {{ presentation.late_data_policy.form.submit.text }}
      </button>
    </form>
  </section>

  <a
    v-if="presentation.historical_workflow_navigation"
    v-bind="presentation.historical_workflow_navigation.attrs"
  >
    <span :class="presentation.historical_workflow_navigation.icon_class"></span>
    {{ presentation.historical_workflow_navigation.text }}
  </a>

  <section v-if="presentation.navigation" v-bind="presentation.navigation.attrs">
    <h3 :class="presentation.navigation.heading.class">{{ presentation.navigation.heading.text }}</h3>
    <button
      v-for="entry in presentation.navigation.entries"
      :key="String(entry.attrs['data-data-link-nav-entry-index'])"
      v-bind="entry.attrs"
    >
      <span class="text-base-content/60">From</span>
      <span class="font-mono text-base-content break-all">{{ entry.from }}</span>
      <span class="text-base-content/60">Via</span>
      <span class="text-base-content break-all">{{ entry.via }}</span>
    </button>
  </section>

  <section v-if="presentation.record" v-bind="presentation.record.attrs">
    <h3 :class="presentation.record.heading.class">{{ presentation.record.heading.text }}</h3>
    <dl :class="presentation.record.list_class">
      <template v-for="row in presentation.record.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class" v-bind="row.value.attrs">{{ row.value.text }}</dd>
      </template>
    </dl>
  </section>

  <section v-if="presentation.related" v-bind="presentation.related.attrs">
    <h3 :class="presentation.related.heading.class">{{ presentation.related.heading.text }}</h3>
    <div :class="presentation.related.groups_class">
      <div
        v-for="group in presentation.related.groups"
        :key="String(group.attrs['data-data-link-related-group'])"
        v-bind="group.attrs"
      >
        <div :class="group.header_class">
          <h4 :class="group.heading.class">{{ group.heading.text }}</h4>
          <span :class="group.count.class">{{ group.count.text }}</span>
        </div>
        <button
          v-for="link in group.links"
          :key="String(link.attrs['data-data-link-related-ref'])"
          v-bind="link.attrs"
        >
          <span class="text-base-content/60">{{ link.target }}</span>
          <span class="font-mono text-base-content break-all">{{ link.target_id }}</span>
          <span class="text-base-content/60">Label</span>
          <span class="text-base-content break-all">{{ link.label }}</span>
        </button>
      </div>
    </div>
  </section>

  <section v-if="presentation.runtime_context" v-bind="presentation.runtime_context.attrs">
    <h3 :class="presentation.runtime_context.heading.class">
      {{ presentation.runtime_context.heading.text }}
    </h3>
    <dl :class="presentation.runtime_context.list_class">
      <template v-for="row in presentation.runtime_context.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class" v-bind="row.value.attrs">{{ row.value.text }}</dd>
      </template>
    </dl>
  </section>
</template>
