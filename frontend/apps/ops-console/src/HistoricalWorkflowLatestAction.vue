<script setup lang="ts">
type Attributes = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}

type DetailRowPresentation = {
  key: string
  label: TextPresentation
  value: TextPresentation
}

type HandoffLinkPresentation = {
  key: string
  href: string
  navigation_kind: "patch"
  class: string
  text: string
  attrs: Attributes
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
  message: TextPresentation
  details: {
    class: string
    rows: DetailRowPresentation[]
  }
  handoffs: {
    visible: boolean
    id: string
    class: string
    attrs: Attributes
    header: {
      class: string
      label: TextPresentation
      count: TextPresentation
    }
    links_container: {
      class: string
    }
    links: HandoffLinkPresentation[]
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

    <p :class="presentation.message.class">{{ presentation.message.text }}</p>

    <dl :class="presentation.details.class">
      <template v-for="row in presentation.details.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class">{{ row.value.text }}</dd>
      </template>
    </dl>

    <section
      v-if="presentation.handoffs.visible"
      :id="presentation.handoffs.id"
      :class="presentation.handoffs.class"
      v-bind="presentation.handoffs.attrs"
    >
      <div :class="presentation.handoffs.header.class">
        <span :class="presentation.handoffs.header.label.class">
          {{ presentation.handoffs.header.label.text }}
        </span>
        <span :class="presentation.handoffs.header.count.class">
          {{ presentation.handoffs.header.count.text }}
        </span>
      </div>
      <div :class="presentation.handoffs.links_container.class">
        <a
          v-for="link in presentation.handoffs.links"
          :key="link.key"
          :href="link.href"
          :class="link.class"
          v-bind="link.attrs"
        >
          {{ link.text }}
        </a>
      </div>
    </section>
  </div>
</template>
