<script setup lang="ts">
type DataAttrs = Record<string, string | null>

type IconPresentation = {
  name: string
  class: string
}

type TextPresentation = {
  class: string
  text: string
}

type RootPresentation = {
  id?: string
  class: string
  attrs?: DataAttrs
}

type ReadinessReturnPresentation = {
  kind: "readiness_return"
  visible: boolean
  root: RootPresentation
  message: TextPresentation
  action: {
    type: "button"
    class: string
    text: string
    icon: IconPresentation
    attrs: DataAttrs
  }
}

type SourceActionRow = {
  key: string
  class: string
  attrs: DataAttrs
  message: {text: string}
  occurred_at: TextPresentation
  source: TextPresentation & {visible: boolean}
}

type SourceActionsPresentation = {
  kind: "source_actions"
  visible: boolean
  root: RootPresentation
  latest: TextPresentation
  rows: SourceActionRow[]
}

type LinkPresentation = {
  id?: string
  href: string
  navigation_kind: "navigate" | "patch"
  class: string
  text: string
  icon: IconPresentation
  attrs: DataAttrs
}

type RecoveryPresentation = {
  kind: "recovery"
  visible: boolean
  root: RootPresentation
  message: TextPresentation
  action: LinkPresentation
}

type RemediationRow = {
  key: string
  class: string
  attrs: DataAttrs
  label: TextPresentation
  message: TextPresentation & {visible: boolean}
  action: LinkPresentation | null
}

type RemediationPresentation = {
  kind: "remediation"
  visible: boolean
  root: RootPresentation
  heading: TextPresentation
  rows: RemediationRow[]
}

type Presentation =
  | ReadinessReturnPresentation
  | SourceActionsPresentation
  | RecoveryPresentation
  | RemediationPresentation

defineProps<{presentation: Presentation}>()
</script>

<template>
  <div
    v-if="presentation.kind === 'readiness_return' && presentation.visible"
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <p :class="presentation.message.class">{{ presentation.message.text }}</p>
    <button
      :type="presentation.action.type"
      :class="presentation.action.class"
      v-bind="presentation.action.attrs"
    >
      <span :class="[presentation.action.icon.name, presentation.action.icon.class]"></span>
      {{ presentation.action.text }}
    </button>
  </div>

  <div
    v-else-if="presentation.kind === 'source_actions' && presentation.visible"
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <p :class="presentation.latest.class">{{ presentation.latest.text }}</p>
    <div
      v-for="row in presentation.rows"
      :key="row.key"
      :class="row.class"
      v-bind="row.attrs"
    >
      <span>{{ row.message.text }}</span>
      <span :class="row.occurred_at.class">{{ row.occurred_at.text }}</span>
      <span v-if="row.source.visible" :class="row.source.class">{{ row.source.text }}</span>
    </div>
  </div>

  <div
    v-else-if="presentation.kind === 'recovery' && presentation.visible"
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <p :class="presentation.message.class">{{ presentation.message.text }}</p>
    <a
      :id="presentation.action.id"
      :href="presentation.action.href"
      :class="presentation.action.class"
      v-bind="presentation.action.attrs"
    >
      <span :class="[presentation.action.icon.name, presentation.action.icon.class]"></span>
      {{ presentation.action.text }}
    </a>
  </div>

  <div
    v-else-if="presentation.kind === 'remediation' && presentation.visible"
    :class="presentation.root.class"
  >
    <div :class="presentation.heading.class">{{ presentation.heading.text }}</div>
    <div
      v-for="row in presentation.rows"
      :key="row.key"
      :class="row.class"
      v-bind="row.attrs"
    >
      <div :class="row.label.class">{{ row.label.text }}</div>
      <p v-if="row.message.visible" :class="row.message.class">{{ row.message.text }}</p>
      <a
        v-if="row.action"
        :href="row.action.href"
        :class="row.action.class"
        v-bind="row.action.attrs"
      >
        <span :class="[row.action.icon.name, row.action.icon.class]"></span>
        {{ row.action.text }}
      </a>
    </div>
  </div>
</template>
