<script setup>
import ClipboardButton from "./ClipboardButton.vue"
import {nextTick, onBeforeUnmount, onMounted, onUpdated, ref} from "vue"

const props = defineProps({
  presentation: {type: Object, required: true}
})

const root = ref(null)
const openGroupId = ref(null)

const isOpen = (group) => openGroupId.value === group.overlay.id

const overlayState = (group) => {
  const open = isOpen(group)

  return {
    ariaExpanded: open
      ? group.overlay.trigger.aria_expanded.open
      : group.overlay.trigger.aria_expanded.closed,
    hidden: !open,
    dataOverlayOpen: open ? group.overlay.open_attr : undefined
  }
}

const activeGroup = () =>
  props.presentation.groups.find((group) => group.overlay.id === openGroupId.value)

const openOverlay = () => {
  if (!openGroupId.value) return null
  const overlay = document.getElementById(openGroupId.value)
  return overlay && root.value?.contains(overlay) ? overlay : null
}

const positionPanel = (group) => {
  const panel = document.getElementById(group.overlay.panel.id)
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
  const group = activeGroup()
  if (!openGroupId.value) return

  openGroupId.value = null
  if (restoreFocus && group) {
    nextTick(() => document.getElementById(group.overlay.trigger.id)?.focus())
  }
}

const toggle = async (group, event) => {
  event.preventDefault()
  if (isOpen(group)) {
    close()
    return
  }

  openGroupId.value = group.overlay.id
  await nextTick()
  const overlay = openOverlay()
  if (!overlay) return

  window.dispatchEvent(new CustomEvent("cadence:overlay-opened", {detail: overlay}))
  positionPanel(group)
}

const onDocumentPointerDown = (event) => {
  const overlay = openOverlay()
  if (overlay && !overlay.contains(event.target)) close(false)
}

const onDocumentKeyDown = (event) => {
  if (event.key !== "Escape" || !openGroupId.value) return
  event.preventDefault()
  close()
}

const onOverlayOpened = (event) => {
  const overlay = openOverlay()
  if (overlay && event.detail !== overlay) close(false)
}

onMounted(() => {
  document.addEventListener("pointerdown", onDocumentPointerDown)
  document.addEventListener("keydown", onDocumentKeyDown)
  window.addEventListener("cadence:overlay-opened", onOverlayOpened)
})

onUpdated(() => {
  if (!openGroupId.value) return

  const group = activeGroup()
  if (!group || !openOverlay()) {
    openGroupId.value = null
    return
  }

  positionPanel(group)
})

onBeforeUnmount(() => {
  document.removeEventListener("pointerdown", onDocumentPointerDown)
  document.removeEventListener("keydown", onDocumentKeyDown)
  window.removeEventListener("cadence:overlay-opened", onOverlayOpened)
})
</script>

<template>
  <div
    :id="presentation.root.id"
    ref="root"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <span :class="presentation.label.class">{{ presentation.label.text }}</span>
    <span :class="presentation.status.class">{{ presentation.status.text }}</span>
    <span :class="presentation.summary.class">{{ presentation.summary.text }}</span>
    <div :class="presentation.controls_class">
      <div :id="presentation.copy_host.id" :class="presentation.copy_host.class">
        <ClipboardButton v-bind="presentation.copy_props" />
      </div>
      <button
        :id="presentation.evidence.id"
        :type="presentation.evidence.type"
        :class="presentation.evidence.class"
        :title="presentation.evidence.title"
        :aria-label="presentation.evidence.aria_label"
        v-bind="presentation.evidence.attrs"
      >
        <span
          :class="[presentation.evidence.icon.name, presentation.evidence.icon.class]"
        ></span>
      </button>
      <button
        :id="presentation.capture.id"
        :type="presentation.capture.type"
        :class="presentation.capture.class"
        :title="presentation.capture.title"
        :aria-label="presentation.capture.aria_label"
        v-bind="presentation.capture.attrs"
      >
        <span
          :class="[presentation.capture.icon.name, presentation.capture.icon.class]"
        ></span>
      </button>
      <div
        v-for="group in presentation.groups"
        :id="group.overlay.id"
        :key="group.key"
        :class="group.overlay.class"
        v-bind="group.overlay.attrs"
        :data-overlay-open="overlayState(group).dataOverlayOpen"
      >
        <button
          :id="group.overlay.trigger.id"
          :type="group.overlay.trigger.type"
          :class="group.overlay.trigger.class"
          :aria-expanded="overlayState(group).ariaExpanded"
          v-bind="group.overlay.trigger.attrs"
          @click="toggle(group, $event)"
        >
          <span
            :class="group.badge.class"
            :title="group.badge.title"
            v-bind="group.badge.attrs"
          >
            <span :class="[group.badge.icon.name, group.badge.icon.class]"></span>
            <span>{{ group.badge.label }}</span>
            <span :class="group.badge.count_class">{{ group.badge.count }}</span>
          </span>
        </button>
        <section
          :id="group.overlay.panel.id"
          :class="group.overlay.panel.class"
          :hidden="overlayState(group).hidden"
          v-bind="group.overlay.panel.attrs"
        >
          <div :class="group.details.class">
            <div :class="group.details.heading.class">
              {{ group.details.heading.text }}
            </div>
            <div :class="group.details.items_class">
              <a
                v-for="item in group.items"
                :key="item.key"
                :href="item.href"
                :class="item.class"
                v-bind="item.attrs"
              >
                <span :class="item.title.class">{{ item.title.text }}</span>
                <span :class="item.reason.class">{{ item.reason.text }}</span>
              </a>
            </div>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>
