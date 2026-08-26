<script setup lang="ts">
import {computed} from "vue"
import CadencePopover from "./ui/reka/CadencePopover.vue"
import WidgetDataLinks from "./WidgetDataLinks.vue"
import WidgetQueryDiagnostics from "./WidgetQueryDiagnostics.vue"
import WidgetWarning from "./WidgetWarning.vue"

type Attrs = Record<string, string>
type Classes = string | string[]

type IconPresentation = {
  name: string
  class: string
}

type BadgePresentation = {
  class: Classes
  text: string
}

type ButtonPresentation = {
  key?: string
  type: string
  class: string
  attrs: Attrs
  icon: IconPresentation
}

type ChildPresentation = {
  component_id: string
  [key: string]: unknown
}

type SourceBadgePresentation = {
  wrapper: {tag: string; class: string} | null
  badge: {
    tag: string
    class: string
    attrs: Attrs
    icon: IconPresentation
    text: string
  }
  inventory_link: {
    tag: string
    class: string
    attrs: Attrs
    icon: IconPresentation
  } | null
}

type DashboardWidgetHeaderPresentation = {
  component_id: string
  root: {class: Classes; attrs: Attrs}
  title: {class: Classes; text: string}
  status_indicators: {
    class: string
    attrs: Attrs
    limit: {
      class: Classes
      dot_class: string
      label_class: string
      text: string
    } | null
    comparison: ({attrs: Attrs} & BadgePresentation) | null
    quality: BadgePresentation | null
    lifecycle: {
      class: Classes
      attrs: Attrs
      icon: IconPresentation
    } | null
  }
  actions: {
    class: Classes
    details: {
      overlay: {id: string; class: string; attrs: Attrs}
      trigger: {
        id: string
        type: string
        class: string
        attrs: Attrs
        content: {class: string; attrs: Attrs; icon: IconPresentation}
      }
      panel: {id: string; class: string; hidden: boolean; attrs: Attrs}
      body: {
        class: string
        heading: {
          class: string
          title: {class: string; text: string}
          binding: {class: string; text: string}
        }
        indicators: {
          class: string
          attrs: Attrs
          lifecycle: BadgePresentation | null
          source: SourceBadgePresentation | null
          data_management: Array<{tag: string; class: string; attrs: Attrs; text: string}>
          warnings: ChildPresentation[]
        }
        actions: {
          class: string
          attrs: Attrs
          query: ChildPresentation | null
          frame_evidence: ButtonPresentation | null
          data_links: ChildPresentation | null
          inspector: ButtonPresentation | null
        }
      }
    }
    edit: ButtonPresentation[]
  }
}

const props = defineProps<{presentation: DashboardWidgetHeaderPresentation}>()
const detailsPanelAttrs = computed(() => {
  const attrs = {...props.presentation.actions.details.panel.attrs}
  delete attrs.hidden
  return attrs
})
</script>

<template>
  <div :class="props.presentation.root.class" v-bind="props.presentation.root.attrs">
    <h3 :class="props.presentation.title.class">{{ props.presentation.title.text }}</h3>
    <div
      :class="props.presentation.status_indicators.class"
      v-bind="props.presentation.status_indicators.attrs"
    >
      <span
        v-if="props.presentation.status_indicators.limit"
        :class="props.presentation.status_indicators.limit.class"
      >
        <span :class="props.presentation.status_indicators.limit.dot_class"></span>
        <span :class="props.presentation.status_indicators.limit.label_class">
          {{ props.presentation.status_indicators.limit.text }}
        </span>
      </span>
      <span
        v-if="props.presentation.status_indicators.comparison"
        :class="props.presentation.status_indicators.comparison.class"
        v-bind="props.presentation.status_indicators.comparison.attrs"
      >
        {{ props.presentation.status_indicators.comparison.text }}
      </span>
      <span
        v-if="props.presentation.status_indicators.quality"
        :class="props.presentation.status_indicators.quality.class"
      >
        {{ props.presentation.status_indicators.quality.text }}
      </span>
      <span
        v-if="props.presentation.status_indicators.lifecycle"
        :class="props.presentation.status_indicators.lifecycle.class"
        v-bind="props.presentation.status_indicators.lifecycle.attrs"
      >
        <span
          :class="[
            props.presentation.status_indicators.lifecycle.icon.name,
            props.presentation.status_indicators.lifecycle.icon.class,
          ]"
        ></span>
      </span>
    </div>
    <div :class="props.presentation.actions.class">
      <CadencePopover
        :id="props.presentation.actions.details.overlay.id"
        :identity="props.presentation.actions.details.overlay.id"
        :class="props.presentation.actions.details.overlay.class"
        v-bind="props.presentation.actions.details.overlay.attrs"
        side="bottom"
        align="end"
        :side-offset="8"
        :collision-padding="16"
      >
        <template #trigger="{open}">
          <button
            :id="props.presentation.actions.details.trigger.id"
            :type="props.presentation.actions.details.trigger.type"
            :class="props.presentation.actions.details.trigger.class"
            v-bind="props.presentation.actions.details.trigger.attrs"
            :aria-expanded="String(open)"
          >
            <span
              :class="props.presentation.actions.details.trigger.content.class"
              v-bind="props.presentation.actions.details.trigger.content.attrs"
            >
              <span
                :class="[
                  props.presentation.actions.details.trigger.content.icon.name,
                  props.presentation.actions.details.trigger.content.icon.class,
                ]"
              ></span>
            </span>
          </button>
        </template>

        <template #content="{open}">
          <section
            :id="props.presentation.actions.details.panel.id"
            :class="props.presentation.actions.details.panel.class"
            v-bind="detailsPanelAttrs"
            :hidden="!open"
          >
            <div :class="props.presentation.actions.details.body.class">
              <div :class="props.presentation.actions.details.body.heading.class">
                <p :class="props.presentation.actions.details.body.heading.title.class">
                  {{ props.presentation.actions.details.body.heading.title.text }}
                </p>
                <p :class="props.presentation.actions.details.body.heading.binding.class">
                  {{ props.presentation.actions.details.body.heading.binding.text }}
                </p>
              </div>
              <div
                :class="props.presentation.actions.details.body.indicators.class"
                v-bind="props.presentation.actions.details.body.indicators.attrs"
              >
                <span
                  v-if="props.presentation.actions.details.body.indicators.lifecycle"
                  :class="props.presentation.actions.details.body.indicators.lifecycle.class"
                >
                  {{ props.presentation.actions.details.body.indicators.lifecycle.text }}
                </span>
                <component
                  :is="props.presentation.actions.details.body.indicators.source.wrapper.tag"
                  v-if="props.presentation.actions.details.body.indicators.source?.wrapper"
                  :class="props.presentation.actions.details.body.indicators.source.wrapper.class"
                >
                  <component
                    :is="props.presentation.actions.details.body.indicators.source.badge.tag"
                    :class="props.presentation.actions.details.body.indicators.source.badge.class"
                    v-bind="props.presentation.actions.details.body.indicators.source.badge.attrs"
                  >
                    <span
                      :class="[
                        props.presentation.actions.details.body.indicators.source.badge.icon.name,
                        props.presentation.actions.details.body.indicators.source.badge.icon.class,
                      ]"
                    ></span>
                    <span>{{ props.presentation.actions.details.body.indicators.source.badge.text }}</span>
                  </component>
                  <a
                    v-if="props.presentation.actions.details.body.indicators.source.inventory_link"
                    :class="props.presentation.actions.details.body.indicators.source.inventory_link.class"
                    v-bind="props.presentation.actions.details.body.indicators.source.inventory_link.attrs"
                  >
                    <span
                      :class="[
                        props.presentation.actions.details.body.indicators.source.inventory_link.icon.name,
                        props.presentation.actions.details.body.indicators.source.inventory_link.icon.class,
                      ]"
                    ></span>
                  </a>
                </component>
                <component
                  :is="props.presentation.actions.details.body.indicators.source.badge.tag"
                  v-else-if="props.presentation.actions.details.body.indicators.source"
                  :class="props.presentation.actions.details.body.indicators.source.badge.class"
                  v-bind="props.presentation.actions.details.body.indicators.source.badge.attrs"
                >
                  <span
                    :class="[
                      props.presentation.actions.details.body.indicators.source.badge.icon.name,
                      props.presentation.actions.details.body.indicators.source.badge.icon.class,
                    ]"
                  ></span>
                  <span>{{ props.presentation.actions.details.body.indicators.source.badge.text }}</span>
                </component>
                <component
                  :is="badge.tag"
                  v-for="(badge, index) in props.presentation.actions.details.body.indicators.data_management"
                  :key="`data-management-${index}`"
                  :class="badge.class"
                  v-bind="badge.attrs"
                >
                  {{ badge.text }}
                </component>
                <div
                  v-for="warning in props.presentation.actions.details.body.indicators.warnings"
                  :id="warning.component_id"
                  :key="warning.component_id"
                  class="contents"
                >
                  <WidgetWarning :presentation="warning" />
                </div>
              </div>
              <div
                :class="props.presentation.actions.details.body.actions.class"
                v-bind="props.presentation.actions.details.body.actions.attrs"
              >
                <div
                  v-if="props.presentation.actions.details.body.actions.query"
                  :id="props.presentation.actions.details.body.actions.query.component_id"
                  class="contents"
                >
                  <WidgetQueryDiagnostics
                    :presentation="props.presentation.actions.details.body.actions.query"
                  />
                </div>
                <button
                  v-if="props.presentation.actions.details.body.actions.frame_evidence"
                  :type="props.presentation.actions.details.body.actions.frame_evidence.type"
                  :class="props.presentation.actions.details.body.actions.frame_evidence.class"
                  v-bind="props.presentation.actions.details.body.actions.frame_evidence.attrs"
                >
                  <span
                    :class="[
                      props.presentation.actions.details.body.actions.frame_evidence.icon.name,
                      props.presentation.actions.details.body.actions.frame_evidence.icon.class,
                    ]"
                  ></span>
                </button>
                <div
                  v-if="props.presentation.actions.details.body.actions.data_links"
                  :id="props.presentation.actions.details.body.actions.data_links.component_id"
                  class="contents"
                >
                  <WidgetDataLinks
                    :presentation="props.presentation.actions.details.body.actions.data_links"
                  />
                </div>
                <button
                  v-if="props.presentation.actions.details.body.actions.inspector"
                  :type="props.presentation.actions.details.body.actions.inspector.type"
                  :class="props.presentation.actions.details.body.actions.inspector.class"
                  v-bind="props.presentation.actions.details.body.actions.inspector.attrs"
                >
                  <span
                    :class="[
                      props.presentation.actions.details.body.actions.inspector.icon.name,
                      props.presentation.actions.details.body.actions.inspector.icon.class,
                    ]"
                  ></span>
                </button>
              </div>
            </div>
          </section>
        </template>
      </CadencePopover>
      <button
        v-for="action in props.presentation.actions.edit"
        :key="action.key"
        :type="action.type"
        :class="action.class"
        v-bind="action.attrs"
      >
        <span :class="[action.icon.name, action.icon.class]"></span>
      </button>
    </div>
  </div>
</template>
