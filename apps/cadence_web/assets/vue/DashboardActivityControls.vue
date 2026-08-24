<script setup lang="ts">
type Attributes = Record<string, string>

type HeaderItem = {
  key: string
  order: number
  tag: "h3" | "span" | "button"
  visible: boolean
  id: string | null
  type: string | null
  class: string
  attrs: Attributes
  text: string
}

type Filter = {
  key: string
  order: number
  tag: "button"
  id: string
  type: "button"
  class: string
  attrs: Attributes
  text: string
}

type DashboardActivityControlsPresentation = {
  header: {
    class: string
    leading_class: string
    items: HeaderItem[]
    count: {
      class: string
      text: string
    }
  }
  controls: {
    id: string
    class: string
    attrs: Attributes
    filters: Filter[]
  }
}

defineProps<{presentation: DashboardActivityControlsPresentation}>()
</script>

<template>
  <div :class="presentation.header.class">
    <div :class="presentation.header.leading_class">
      <template v-for="item in presentation.header.items" :key="item.key">
        <component
          :is="item.tag"
          v-if="item.visible"
          :id="item.id"
          :type="item.type"
          :class="item.class"
          v-bind="item.attrs"
        >{{ item.text }}</component>
      </template>
    </div>
    <span :class="presentation.header.count.class">{{ presentation.header.count.text }}</span>
  </div>
  <div
    :id="presentation.controls.id"
    :class="presentation.controls.class"
    v-bind="presentation.controls.attrs"
  >
    <component
      :is="filter.tag"
      v-for="filter in presentation.controls.filters"
      :id="filter.id"
      :key="filter.key"
      :type="filter.type"
      :class="filter.class"
      v-bind="filter.attrs"
    >{{ filter.text }}</component>
  </div>
</template>
