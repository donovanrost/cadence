<script setup lang="ts">
import {computed} from "vue"
import CadencePopover from "./ui/reka/CadencePopover.vue"

type Attrs = Record<string, string | null>

type IconPresentation = {
  name: string
  class: string
}

type ItemPresentation = {
  key: string
  kind: "data_link" | "evidence"
  type: string
  class: string
  attrs: Attrs
  label: {text: string; class: string | null}
  secondary: {text: string; class: string} | null
  icon: IconPresentation | null
}

type WidgetDataLinksPresentation = {
  kind:
    | "widget"
    | "status_matrix_row"
    | "data_table_row"
    | "state_timeline_row"
    | "event_timeline_row"
  component_id: string
  overlay: {id: string; class: string; attrs: Attrs}
  trigger: {
    id: string
    type: string
    class: string
    attrs: Attrs
    content: {
      class: string
      title: string
      attrs: Attrs
      icon: IconPresentation
    }
  }
  panel: {id: string; class: string; hidden: boolean; attrs: Attrs}
  body: {class: string}
  items: ItemPresentation[]
}

const props = defineProps<{presentation: WidgetDataLinksPresentation}>()

const panelAttrs = computed(() => {
  const attrs = {...props.presentation.panel.attrs}
  delete attrs.hidden
  return attrs
})
</script>

<template>
  <CadencePopover
    :id="props.presentation.overlay.id"
    :identity="props.presentation.overlay.id"
    :class="props.presentation.overlay.class"
    v-bind="props.presentation.overlay.attrs"
    side="bottom"
    align="end"
    :side-offset="8"
    :collision-padding="16"
  >
    <template #trigger="{open}">
      <button
        :id="props.presentation.trigger.id"
        :type="props.presentation.trigger.type"
        :class="props.presentation.trigger.class"
        v-bind="props.presentation.trigger.attrs"
        :aria-expanded="String(open)"
      >
        <span
          :class="props.presentation.trigger.content.class"
          :title="props.presentation.trigger.content.title"
          v-bind="props.presentation.trigger.content.attrs"
        >
          <span
            :class="[
              props.presentation.trigger.content.icon.name,
              props.presentation.trigger.content.icon.class,
            ]"
          ></span>
        </span>
      </button>
    </template>

    <template #content="{open}">
      <section
        :id="props.presentation.panel.id"
        :class="props.presentation.panel.class"
        v-bind="panelAttrs"
        :hidden="!open"
      >
        <div :class="props.presentation.body.class">
          <button
            v-for="item in props.presentation.items"
            :key="item.key"
            :type="item.type"
            :class="item.class"
            v-bind="item.attrs"
          >
            <span :class="item.label.class">{{ item.label.text }}</span>
            <span v-if="item.secondary" :class="item.secondary.class">
              {{ item.secondary.text }}
            </span>
            <span
              v-if="item.icon"
              :class="[item.icon.name, item.icon.class]"
            ></span>
          </button>
        </div>
      </section>
    </template>
  </CadencePopover>
</template>
