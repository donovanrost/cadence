<script setup lang="ts">
type Attributes = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}

type IconPresentation = {
  name: string
  class: string
}

type ButtonPresentation = {
  id: string
  type: "button"
  class: string
  text: string
  icon: IconPresentation
  attrs: Attributes
}

type PatchLinkPresentation = {
  key?: string
  href: string | null
  navigation_kind: "patch"
  class: string
  text: string
  attrs: Attributes
}

type ReviewLinkPresentation = PatchLinkPresentation & {
  icon: IconPresentation
}

type Presentation = {
  root: {
    id: string
    class: string
    attrs: Attributes
  }
  header: {
    class: string
    label: TextPresentation
    status: TextPresentation
  }
  guidance: {
    id: string
    class: string
    attrs: Attributes
    header: {
      class: string
      label: TextPresentation
      next_action: TextPresentation
    }
    guidance: TextPresentation
    policy_state: TextPresentation & {visible: boolean}
    available_when: TextPresentation & {visible: boolean}
  }
  review_origin: {
    visible: boolean
    id: string
    class: string
    attrs: Attributes
    header: {
      class: string
      label: TextPresentation
    }
    review_link: ReviewLinkPresentation
    placements: {
      visible: boolean
      class: string
      attrs: Attributes
      links: PatchLinkPresentation[]
    }
  }
  details: {
    class: string
    rows: Array<{
      key: string
      label: TextPresentation
      value: TextPresentation
    }>
  }
  retry_button: ButtonPresentation & {visible: boolean}
  stale_actions: {
    visible: boolean
    id: string
    class: string
    attrs: Attributes
    buttons: ButtonPresentation[]
  }
  missing_actions: {
    visible: boolean
    id: string
    class: string
    attrs: Attributes
    buttons: ButtonPresentation[]
  }
}

defineProps<{presentation: Presentation}>()
</script>

<template>
  <div
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <div :class="presentation.header.class">
      <span :class="presentation.header.label.class">{{ presentation.header.label.text }}</span>
      <span :class="presentation.header.status.class">{{ presentation.header.status.text }}</span>
    </div>

    <section
      :id="presentation.guidance.id"
      :class="presentation.guidance.class"
      v-bind="presentation.guidance.attrs"
    >
      <div :class="presentation.guidance.header.class">
        <span :class="presentation.guidance.header.label.class">
          {{ presentation.guidance.header.label.text }}
        </span>
        <span :class="presentation.guidance.header.next_action.class">
          {{ presentation.guidance.header.next_action.text }}
        </span>
      </div>
      <p :class="presentation.guidance.guidance.class">
        {{ presentation.guidance.guidance.text }}
      </p>
      <p
        v-if="presentation.guidance.policy_state.visible"
        :class="presentation.guidance.policy_state.class"
      >
        {{ presentation.guidance.policy_state.text }}
      </p>
      <p
        v-if="presentation.guidance.available_when.visible"
        :class="presentation.guidance.available_when.class"
      >
        {{ presentation.guidance.available_when.text }}
      </p>
    </section>

    <section
      v-if="presentation.review_origin.visible"
      :id="presentation.review_origin.id"
      :class="presentation.review_origin.class"
      v-bind="presentation.review_origin.attrs"
    >
      <div :class="presentation.review_origin.header.class">
        <span :class="presentation.review_origin.header.label.class">
          {{ presentation.review_origin.header.label.text }}
        </span>
        <a
          :href="presentation.review_origin.review_link.href"
          :class="presentation.review_origin.review_link.class"
          v-bind="presentation.review_origin.review_link.attrs"
        >
          <span
            :class="[
              presentation.review_origin.review_link.icon.name,
              presentation.review_origin.review_link.icon.class,
            ]"
          ></span>
          {{ presentation.review_origin.review_link.text }}
        </a>
      </div>
      <div
        v-if="presentation.review_origin.placements.visible"
        :class="presentation.review_origin.placements.class"
        v-bind="presentation.review_origin.placements.attrs"
      >
        <a
          v-for="link in presentation.review_origin.placements.links"
          :key="link.key"
          :href="link.href"
          :class="link.class"
          v-bind="link.attrs"
        >
          {{ link.text }}
        </a>
      </div>
    </section>

    <div :class="presentation.details.class">
      <template v-for="row in presentation.details.rows" :key="row.key">
        <span :class="row.label.class">{{ row.label.text }}</span>
        <span :class="row.value.class">{{ row.value.text }}</span>
      </template>
    </div>

    <button
      v-if="presentation.retry_button.visible"
      :id="presentation.retry_button.id"
      :type="presentation.retry_button.type"
      :class="presentation.retry_button.class"
      v-bind="presentation.retry_button.attrs"
    >
      <span
        :class="[presentation.retry_button.icon.name, presentation.retry_button.icon.class]"
      ></span>
      {{ presentation.retry_button.text }}
    </button>

    <div
      v-if="presentation.stale_actions.visible"
      :id="presentation.stale_actions.id"
      :class="presentation.stale_actions.class"
      v-bind="presentation.stale_actions.attrs"
    >
      <button
        v-for="button in presentation.stale_actions.buttons"
        :id="button.id"
        :key="button.id"
        :type="button.type"
        :class="button.class"
        v-bind="button.attrs"
      >
        <span :class="[button.icon.name, button.icon.class]"></span>
        {{ button.text }}
      </button>
    </div>

    <div
      v-if="presentation.missing_actions.visible"
      :id="presentation.missing_actions.id"
      :class="presentation.missing_actions.class"
      v-bind="presentation.missing_actions.attrs"
    >
      <button
        v-for="button in presentation.missing_actions.buttons"
        :id="button.id"
        :key="button.id"
        :type="button.type"
        :class="button.class"
        v-bind="button.attrs"
      >
        <span :class="[button.icon.name, button.icon.class]"></span>
        {{ button.text }}
      </button>
    </div>
  </div>
</template>
