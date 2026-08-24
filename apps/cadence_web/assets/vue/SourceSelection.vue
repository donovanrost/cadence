<script setup lang="ts">
import {nextTick, onBeforeUnmount, onMounted, onUpdated, ref} from "vue"

type DataAttrs = Record<string, string | null>

type TextPresentation = {
  text: string
  class: string
}

type IconPresentation = {
  name: string
  class: string
}

type SelectionFact = {
  label: string
  label_class: string
  value: string
  value_class: string
}

type CandidateAction = {
  href: string
  class: string
  title: string
  label: string
  icon: IconPresentation
  attrs: DataAttrs
}

type ProductSummary = TextPresentation & {
  attrs: DataAttrs
}

type CandidatePresentation = {
  key: string
  class: string
  attrs: DataAttrs
  binding: TextPresentation
  data_source: TextPresentation
  decision: TextPresentation
  reason: TextPresentation
  window: TextPresentation
  action: CandidateAction | null
  product_summary: ProductSummary | null
}

type SelectionPresentation = {
  overlay: {
    id: string
    class: string
    trigger_id: string
    trigger_class: string
    panel_id: string
    panel_class: string
    placement: string
    width: string
    label: string
    attrs: DataAttrs
  }
  badge: {
    class: string
    title: string
    label: string
    icon: IconPresentation
    attrs: DataAttrs
  }
  details: {
    class: string
    header_class: string
    identity_class: string
    heading: TextPresentation
    request_id: TextPresentation
    state: TextPresentation
    facts_class: string
    facts: SelectionFact[]
    candidates_class: string
  }
  candidates: CandidatePresentation[]
}

type SourceSelectionPresentation = {
  id: string
  class: string
  label: TextPresentation
  attrs: DataAttrs
  selections: SelectionPresentation[]
}

const props = defineProps<{presentation: SourceSelectionPresentation}>()

const root = ref<HTMLElement | null>(null)
const openSelectionId = ref<string | null>(null)

const isOpen = (selection: SelectionPresentation) =>
  openSelectionId.value === selection.overlay.id

const openOverlay = () => {
  if (!openSelectionId.value) return null
  const overlay = document.getElementById(openSelectionId.value)
  return overlay && root.value?.contains(overlay) ? overlay : null
}

const positionPanel = (selection: SelectionPresentation) => {
  const panel = document.getElementById(selection.overlay.panel_id)
  if (!(panel instanceof HTMLElement)) return

  panel.style.transform = ""
  const rect = panel.getBoundingClientRect()
  const gutter = 16
  let offset = 0
  if (rect.left < gutter) offset = gutter - rect.left
  if (rect.right + offset > window.innerWidth - gutter) {
    offset -= rect.right + offset - (window.innerWidth - gutter)
  }
  if (offset) panel.style.transform = `translateX(${Math.round(offset)}px)`
}

const close = (restoreFocus = true) => {
  const selectionId = openSelectionId.value
  if (!selectionId) return

  openSelectionId.value = null
  if (restoreFocus) {
    nextTick(() => document.getElementById(`${selectionId}-trigger`)?.focus())
  }
}

const toggle = async (selection: SelectionPresentation, event: MouseEvent) => {
  event.preventDefault()
  if (isOpen(selection)) {
    close()
    return
  }

  openSelectionId.value = selection.overlay.id
  await nextTick()
  const overlay = openOverlay()
  if (!overlay) return

  window.dispatchEvent(new CustomEvent("cadence:overlay-opened", {detail: overlay}))
  positionPanel(selection)
}

const onDocumentPointerDown = (event: PointerEvent) => {
  const overlay = openOverlay()
  if (overlay && !overlay.contains(event.target as Node)) close(false)
}

const onDocumentKeyDown = (event: KeyboardEvent) => {
  if (event.key !== "Escape" || !openSelectionId.value) return
  event.preventDefault()
  close()
}

const onOverlayOpened = (event: Event) => {
  const overlay = openOverlay()
  if (overlay && (event as CustomEvent<HTMLElement>).detail !== overlay) close(false)
}

onMounted(() => {
  document.addEventListener("pointerdown", onDocumentPointerDown)
  document.addEventListener("keydown", onDocumentKeyDown)
  window.addEventListener("cadence:overlay-opened", onOverlayOpened)
})

onUpdated(() => {
  if (!openSelectionId.value) return

  const selection = props.presentation.selections.find(
    (item) => item.overlay.id === openSelectionId.value,
  )

  if (!selection || !openOverlay()) {
    openSelectionId.value = null
    return
  }

  positionPanel(selection)
})

onBeforeUnmount(() => {
  document.removeEventListener("pointerdown", onDocumentPointerDown)
  document.removeEventListener("keydown", onDocumentKeyDown)
  window.removeEventListener("cadence:overlay-opened", onOverlayOpened)
})
</script>

<template>
  <div
    :id="presentation.id"
    ref="root"
    :class="presentation.class"
    v-bind="presentation.attrs"
  >
    <span :class="presentation.label.class">{{ presentation.label.text }}</span>
    <div
      v-for="selection in presentation.selections"
      :id="selection.overlay.id"
      :key="selection.overlay.id"
      :class="selection.overlay.class"
      :data-overlay-open="isOpen(selection) ? '' : undefined"
      data-overlay-kind="popover"
      :data-overlay-placement="selection.overlay.placement"
      v-bind="selection.overlay.attrs"
    >
      <button
        :id="selection.overlay.trigger_id"
        type="button"
        data-overlay-trigger
        aria-haspopup="dialog"
        :aria-expanded="String(isOpen(selection))"
        :aria-controls="selection.overlay.panel_id"
        :aria-label="selection.overlay.label"
        :class="selection.overlay.trigger_class"
        @click="toggle(selection, $event)"
      >
        <span
          :class="selection.badge.class"
          :title="selection.badge.title"
          v-bind="selection.badge.attrs"
        >
          <span :class="[selection.badge.icon.name, selection.badge.icon.class]"></span>
          <span>{{ selection.badge.label }}</span>
        </span>
      </button>
      <section
        :id="selection.overlay.panel_id"
        data-overlay-panel
        :data-overlay-width="selection.overlay.width"
        :aria-label="selection.overlay.label"
        :class="selection.overlay.panel_class"
        :hidden="!isOpen(selection)"
      >
        <div :class="selection.details.class">
          <div :class="selection.details.header_class">
            <div :class="selection.details.identity_class">
              <div :class="selection.details.heading.class">
                {{ selection.details.heading.text }}
              </div>
              <div :class="selection.details.request_id.class">
                {{ selection.details.request_id.text }}
              </div>
            </div>
            <span :class="selection.details.state.class">
              {{ selection.details.state.text }}
            </span>
          </div>
          <dl :class="selection.details.facts_class">
            <template v-for="fact in selection.details.facts" :key="fact.label">
              <dt :class="fact.label_class">{{ fact.label }}</dt>
              <dd :class="fact.value_class">{{ fact.value }}</dd>
            </template>
          </dl>
          <div
            v-if="selection.candidates.length > 0"
            :class="selection.details.candidates_class"
          >
            <div
              v-for="candidate in selection.candidates"
              :key="candidate.key"
              :class="candidate.class"
              v-bind="candidate.attrs"
            >
              <span :class="candidate.binding.class">{{ candidate.binding.text }}</span>
              <span :class="candidate.data_source.class">{{ candidate.data_source.text }}</span>
              <span :class="candidate.decision.class">{{ candidate.decision.text }}</span>
              <span :class="candidate.reason.class">{{ candidate.reason.text }}</span>
              <span :class="candidate.window.class">{{ candidate.window.text }}</span>
              <a
                v-if="candidate.action"
                :href="candidate.action.href"
                :class="candidate.action.class"
                :title="candidate.action.title"
                v-bind="candidate.action.attrs"
              >
                <span :class="[candidate.action.icon.name, candidate.action.icon.class]"></span>
                {{ candidate.action.label }}
              </a>
              <span
                v-if="candidate.product_summary"
                :class="candidate.product_summary.class"
                v-bind="candidate.product_summary.attrs"
              >
                {{ candidate.product_summary.text }}
              </span>
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
