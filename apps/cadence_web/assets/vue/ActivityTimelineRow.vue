<script setup lang="ts">
import ClipboardButton from "./ClipboardButton.vue"
import ComparisonReviewActivityDetails from "./ComparisonReviewActivityDetails.vue"
import HealthSnapshotActivity from "./HealthSnapshotActivity.vue"

type Attributes = Record<string, string>

type TextPresentation = {
  class: string | string[]
  text: string
}

type BadgePresentation = TextPresentation & {
  attrs: Attributes
  visible?: boolean
}

type ChildPresentation = {
  id: string
  class: string
  attrs: Attributes
  presentation: Record<string, unknown>
}

type Presentation = {
  root: {
    id: string
    class: string[]
    attrs: Attributes
  }
  header: {
    class: string
    title: TextPresentation
    version: TextPresentation
    selected_badge: BadgePresentation
    readiness_badge: BadgePresentation | null
    remediation_badge: BadgePresentation
    remediation_actions: Array<
      BadgePresentation & {
        key: string
        order: number
      }
    >
  }
  fields: {
    class: string
    rows: Array<{
      key: string
      order: number
      label: TextPresentation
      value: TextPresentation & { attrs: Attributes }
    }>
  }
  actions: {
    class: string
    select: {
      id: string
      type: "button"
      class: string
      attrs: Attributes
      icon: { name: string; class: string }
      text: string
    }
    copy_host: {
      id: string
      class: string
      attrs: Attributes
    }
    copy_props: Record<string, unknown>
  }
  comparison_review: {
    request: ChildPresentation | null
    resolution: ChildPresentation | null
  }
  health_snapshot: ChildPresentation | null
}

defineProps<{ presentation: Presentation }>()
</script>

<template>
  <li
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <div :class="presentation.header.class">
      <span :class="presentation.header.title.class">
        {{ presentation.header.title.text }}
      </span>
      <span :class="presentation.header.version.class">
        {{ presentation.header.version.text }}
      </span>
      <span
        v-if="presentation.header.selected_badge.visible"
        :class="presentation.header.selected_badge.class"
        v-bind="presentation.header.selected_badge.attrs"
      >
        {{ presentation.header.selected_badge.text }}
      </span>
      <span
        v-if="presentation.header.readiness_badge"
        :class="presentation.header.readiness_badge.class"
        v-bind="presentation.header.readiness_badge.attrs"
      >
        {{ presentation.header.readiness_badge.text }}
      </span>
      <span
        v-if="presentation.header.remediation_badge.visible"
        :class="presentation.header.remediation_badge.class"
        v-bind="presentation.header.remediation_badge.attrs"
      >
        {{ presentation.header.remediation_badge.text }}
      </span>
      <span
        v-for="action in presentation.header.remediation_actions"
        :key="action.key"
        :class="action.class"
        v-bind="action.attrs"
      >
        {{ action.text }}
      </span>
    </div>

    <dl :class="presentation.fields.class">
      <template v-for="field in presentation.fields.rows" :key="field.key">
        <dt :class="field.label.class">{{ field.label.text }}</dt>
        <dd :class="field.value.class" v-bind="field.value.attrs">
          {{ field.value.text }}
        </dd>
      </template>
    </dl>

    <div :class="presentation.actions.class">
      <button
        :id="presentation.actions.select.id"
        :type="presentation.actions.select.type"
        :class="presentation.actions.select.class"
        v-bind="presentation.actions.select.attrs"
      >
        <span
          :class="[
            presentation.actions.select.icon.name,
            presentation.actions.select.icon.class,
          ]"
        ></span>
        {{ presentation.actions.select.text }}
      </button>
      <div
        :id="presentation.actions.copy_host.id"
        :class="presentation.actions.copy_host.class"
        v-bind="presentation.actions.copy_host.attrs"
      >
        <ClipboardButton v-bind="presentation.actions.copy_props" />
      </div>
    </div>

    <div
      v-if="presentation.comparison_review.request"
      :id="presentation.comparison_review.request.id"
      :class="presentation.comparison_review.request.class"
      v-bind="presentation.comparison_review.request.attrs"
    >
      <ComparisonReviewActivityDetails
        :presentation="presentation.comparison_review.request.presentation"
      />
    </div>
    <div
      v-if="presentation.comparison_review.resolution"
      :id="presentation.comparison_review.resolution.id"
      :class="presentation.comparison_review.resolution.class"
      v-bind="presentation.comparison_review.resolution.attrs"
    >
      <ComparisonReviewActivityDetails
        :presentation="presentation.comparison_review.resolution.presentation"
      />
    </div>
    <div
      v-if="presentation.health_snapshot"
      :id="presentation.health_snapshot.id"
      :class="presentation.health_snapshot.class"
      v-bind="presentation.health_snapshot.attrs"
    >
      <HealthSnapshotActivity
        :presentation="presentation.health_snapshot.presentation"
      />
    </div>
  </li>
</template>
