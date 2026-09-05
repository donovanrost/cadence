<script setup lang="ts">
type AttributeValue = string | boolean | null
type Attributes = Record<string, AttributeValue>

type QuickRangeItem = {
  key: string
  attrs: Attributes
  indicator_class: string | null
  label: string
}

type DashboardQuickRangeListPresentation = {
  root: {
    attrs: Attributes
  }
  search: {
    form: {
      attrs: Attributes
    }
    field: {
      wrapper_class: string
      attrs: Attributes
    }
  }
  presets: {
    attrs: Attributes
    items: QuickRangeItem[]
  }
}

defineProps<{presentation: DashboardQuickRangeListPresentation}>()
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <form v-bind="presentation.search.form.attrs">
      <div :class="presentation.search.field.wrapper_class">
        <label>
          <input v-bind="presentation.search.field.attrs" />
        </label>
      </div>
    </form>
    <ul v-bind="presentation.presets.attrs">
      <li v-for="item in presentation.presets.items" :key="item.key">
        <button v-bind="item.attrs">
          <span v-if="item.indicator_class" :class="item.indicator_class"></span>
          {{ item.label }}
        </button>
      </li>
    </ul>
  </div>
</template>
