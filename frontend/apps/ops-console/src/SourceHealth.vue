<script setup lang="ts">
import {computed} from "vue"
import CadencePopover from "./ui/reka/CadencePopover.vue"

type Attrs = Record<string, string>

type TextPresentation = {
  class: string
  text: string
}

type IconPresentation = {
  name: string
  class: string
}

type DetailRowPresentation = {
  key: string
  order: number
  label: TextPresentation
  value: TextPresentation & {attrs: Attrs}
}

type SourcePresentation = {
  key: string
  order: number
  overlay: {
    id: string
    label: string
    class: string
    placement: string
    width: string
    attrs: Attrs
  }
  trigger: {
    id: string
    type: string
    class: string
    attrs: Attrs
  }
  badge: TextPresentation & {attrs: Attrs}
  panel: {
    id: string
    class: string
    hidden: boolean
    width: string
    attrs: Attrs
  }
  details: {
    class: string
    heading: TextPresentation
    prose: TextPresentation
    circuit: TextPresentation & {visible: boolean}
    evidence: {
      type: string
      class: string
      attrs: Attrs
      icon: IconPresentation
      label: string
    }
    rows_class: string
    rows: DetailRowPresentation[]
  }
}

type SourceHealthPresentation = {
  root: {
    id: string
    class: string
    attrs: Attrs
  }
  label: TextPresentation
  sources: SourcePresentation[]
}

const props = defineProps<{presentation: SourceHealthPresentation}>()

// SOURCE_HEALTH_POPOVER_ENTRIES_START
const sourceHealthPopoverEntries = (sources: SourcePresentation[]) => {
  const occurrenceByOverlayId = new Map<string, number>()

  return sources.map((source) => {
    const occurrence = occurrenceByOverlayId.get(source.overlay.id) ?? 0
    occurrenceByOverlayId.set(source.overlay.id, occurrence + 1)

    return {
      key: JSON.stringify([source.overlay.id, occurrence]),
      occurrence,
      source,
    }
  })
}
// SOURCE_HEALTH_POPOVER_ENTRIES_END

const popoverEntries = computed(() =>
  sourceHealthPopoverEntries(props.presentation.sources),
)
</script>

<template>
  <div
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <span :class="presentation.label.class">{{ presentation.label.text }}</span>
    <CadencePopover
      v-for="entry in popoverEntries"
      :id="entry.source.overlay.id"
      :key="entry.key"
      :identity="entry.source.overlay.id"
      :class="entry.source.overlay.class"
      v-bind="entry.source.overlay.attrs"
      side="bottom"
      align="end"
      :side-offset="8"
      :collision-padding="16"
    >
      <template #trigger="{open}">
        <button
          :id="entry.source.trigger.id"
          :type="entry.source.trigger.type"
          :class="entry.source.trigger.class"
          v-bind="entry.source.trigger.attrs"
          :aria-expanded="String(open)"
        >
          <span :class="entry.source.badge.class" v-bind="entry.source.badge.attrs">
            {{ entry.source.badge.text }}
          </span>
        </button>
      </template>

      <template #content="{open}">
        <section
          :id="entry.source.panel.id"
          :class="entry.source.panel.class"
          v-bind="entry.source.panel.attrs"
          :hidden="!open"
        >
          <div :class="entry.source.details.class">
            <div :class="entry.source.details.heading.class">
              {{ entry.source.details.heading.text }}
            </div>
            <p :class="entry.source.details.prose.class">
              {{ entry.source.details.prose.text }}
            </p>
            <p
              v-if="entry.source.details.circuit.visible"
              :class="entry.source.details.circuit.class"
            >
              {{ entry.source.details.circuit.text }}
            </p>
            <button
              :type="entry.source.details.evidence.type"
              :class="entry.source.details.evidence.class"
              v-bind="entry.source.details.evidence.attrs"
            >
              <span
                :class="[
                  entry.source.details.evidence.icon.name,
                  entry.source.details.evidence.icon.class,
                ]"
              ></span>
              {{ entry.source.details.evidence.label }}
            </button>
            <dl :class="entry.source.details.rows_class">
              <template v-for="row in entry.source.details.rows" :key="row.key">
                <dt :class="row.label.class">{{ row.label.text }}</dt>
                <dd :class="row.value.class" v-bind="row.value.attrs">
                  {{ row.value.text }}
                </dd>
              </template>
            </dl>
          </div>
        </section>
      </template>
    </CadencePopover>
  </div>
</template>
