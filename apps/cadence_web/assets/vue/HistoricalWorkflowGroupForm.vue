<script setup lang="ts">
type Attributes = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}

type DetailRowPresentation = {
  label: TextPresentation
  value: TextPresentation
}

type EligibleActionPresentation = {
  key: string
  attrs: Attributes
  header: {
    class: string
    label: TextPresentation
    count: TextPresentation
  }
  preview: TextPresentation
  state_summary: TextPresentation | null
  available_when: TextPresentation | null
}

type ActionPresentation = {
  key: string
  attrs: Attributes
  label: TextPresentation & {
    icon: {
      name: string
      class: string
    }
  }
  count: TextPresentation
}

type Presentation = {
  root: {
    id: string
    class: string
    attrs: Attributes
  }
  hidden_fields: Array<{
    key: string
    attrs: Attributes
  }>
  header: {
    class: string
    title: TextPresentation
    count: TextPresentation
  }
  eligible_items: {
    id: string
    class: string
    attrs: Attributes
    header: {
      class: string
      title: TextPresentation
      count: TextPresentation
    }
    list_class: string
    actions: EligibleActionPresentation[]
  }
  start_orchestration: null | {
    id: string
    class: string
    attrs: Attributes
    header: {
      class: string
      title: TextPresentation
      count: TextPresentation
    }
    guidance: TextPresentation
    details: {
      class: string
      eligible: DetailRowPresentation
      review: DetailRowPresentation | null
      state: DetailRowPresentation | null
    }
    available_when: TextPresentation | null
  }
  reason: {
    wrapper_class: string
    label: TextPresentation
    control: {
      class: string
      attrs: Attributes
    }
    errors: TextPresentation[]
  }
  confirmation: {
    id: string
    class: string
    field: {
      class: string
      attrs: Attributes
    }
    label: TextPresentation
  }
  actions: {
    class: string
    items: ActionPresentation[]
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
      :key="field.key"
      v-bind="field.attrs"
    >

    <div :class="presentation.header.class">
      <h4 :class="presentation.header.title.class">{{ presentation.header.title.text }}</h4>
      <span :class="presentation.header.count.class">{{ presentation.header.count.text }}</span>
    </div>

    <div
      :id="presentation.eligible_items.id"
      :class="presentation.eligible_items.class"
      v-bind="presentation.eligible_items.attrs"
    >
      <div :class="presentation.eligible_items.header.class">
        <span :class="presentation.eligible_items.header.title.class">
          {{ presentation.eligible_items.header.title.text }}
        </span>
        <span :class="presentation.eligible_items.header.count.class">
          {{ presentation.eligible_items.header.count.text }}
        </span>
      </div>
      <div :class="presentation.eligible_items.list_class">
        <div
          v-for="action in presentation.eligible_items.actions"
          :key="action.key"
          v-bind="action.attrs"
        >
          <div :class="action.header.class">
            <span :class="action.header.label.class">{{ action.header.label.text }}</span>
            <span :class="action.header.count.class">{{ action.header.count.text }}</span>
          </div>
          <p :class="action.preview.class">{{ action.preview.text }}</p>
          <p v-if="action.state_summary" :class="action.state_summary.class">
            {{ action.state_summary.text }}
          </p>
          <p v-if="action.available_when" :class="action.available_when.class">
            {{ action.available_when.text }}
          </p>
        </div>
      </div>
    </div>

    <section
      v-if="presentation.start_orchestration"
      :id="presentation.start_orchestration.id"
      :class="presentation.start_orchestration.class"
      v-bind="presentation.start_orchestration.attrs"
    >
      <div :class="presentation.start_orchestration.header.class">
        <span :class="presentation.start_orchestration.header.title.class">
          {{ presentation.start_orchestration.header.title.text }}
        </span>
        <span :class="presentation.start_orchestration.header.count.class">
          {{ presentation.start_orchestration.header.count.text }}
        </span>
      </div>
      <p :class="presentation.start_orchestration.guidance.class">
        {{ presentation.start_orchestration.guidance.text }}
      </p>
      <dl :class="presentation.start_orchestration.details.class">
        <dt :class="presentation.start_orchestration.details.eligible.label.class">
          {{ presentation.start_orchestration.details.eligible.label.text }}
        </dt>
        <dd :class="presentation.start_orchestration.details.eligible.value.class">
          {{ presentation.start_orchestration.details.eligible.value.text }}
        </dd>
        <template v-if="presentation.start_orchestration.details.review">
          <dt :class="presentation.start_orchestration.details.review.label.class">
            {{ presentation.start_orchestration.details.review.label.text }}
          </dt>
          <dd :class="presentation.start_orchestration.details.review.value.class">
            {{ presentation.start_orchestration.details.review.value.text }}
          </dd>
        </template>
        <template v-if="presentation.start_orchestration.details.state">
          <dt :class="presentation.start_orchestration.details.state.label.class">
            {{ presentation.start_orchestration.details.state.label.text }}
          </dt>
          <dd :class="presentation.start_orchestration.details.state.value.class">
            {{ presentation.start_orchestration.details.state.value.text }}
          </dd>
        </template>
      </dl>
      <p
        v-if="presentation.start_orchestration.available_when"
        :class="presentation.start_orchestration.available_when.class"
      >
        {{ presentation.start_orchestration.available_when.text }}
      </p>
    </section>

    <div :class="presentation.reason.wrapper_class">
      <label>
        <span :class="presentation.reason.label.class">{{ presentation.reason.label.text }}</span>
        <input :class="presentation.reason.control.class" v-bind="presentation.reason.control.attrs">
      </label>
      <p v-for="error in presentation.reason.errors" :key="error.text" :class="error.class">
        {{ error.text }}
      </p>
    </div>

    <label :id="presentation.confirmation.id" :class="presentation.confirmation.class">
      <input
        :class="presentation.confirmation.field.class"
        v-bind="presentation.confirmation.field.attrs"
      >
      <span :class="presentation.confirmation.label.class">
        {{ presentation.confirmation.label.text }}
      </span>
    </label>

    <div :class="presentation.actions.class">
      <button
        v-for="action in presentation.actions.items"
        :key="action.key"
        v-bind="action.attrs"
      >
        <span :class="action.label.class">
          <span :class="[action.label.icon.name, action.label.icon.class]"></span>
          {{ action.label.text }}
        </span>
        <span :class="action.count.class">{{ action.count.text }}</span>
      </button>
    </div>
  </form>
</template>
