<script setup>
import {nextTick, onBeforeUnmount, onMounted, onUpdated, ref} from "vue"

const props = defineProps({
  presentation: {type: Object, required: true}
})

const root = ref(null)
const openOverlayId = ref(null)

const overlays = () =>
  [props.presentation.saved_presets, props.presentation.details].filter(Boolean)

const isOpen = (overlay) => openOverlayId.value === overlay.root.attrs.id

const overlayState = (overlay) => {
  const open = isOpen(overlay)

  return {
    ariaExpanded: open
      ? overlay.trigger.aria_expanded.open
      : overlay.trigger.aria_expanded.closed,
    hidden: !open,
    dataOverlayOpen: open ? overlay.root.open_attr : undefined
  }
}

const activeOverlay = () =>
  overlays().find((overlay) => overlay.root.attrs.id === openOverlayId.value)

const openOverlay = () => {
  if (!openOverlayId.value) return null
  const overlay = document.getElementById(openOverlayId.value)
  return overlay && root.value?.contains(overlay) ? overlay : null
}

const positionPanel = (overlay) => {
  const panel = document.getElementById(overlay.panel.attrs.id)
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
  const overlay = activeOverlay()
  if (!openOverlayId.value) return

  openOverlayId.value = null
  if (restoreFocus && overlay) {
    nextTick(() => document.getElementById(overlay.trigger.attrs.id)?.focus())
  }
}

const toggle = async (overlay, event) => {
  event.preventDefault()
  if (isOpen(overlay)) {
    close()
    return
  }

  openOverlayId.value = overlay.root.attrs.id
  await nextTick()
  const element = openOverlay()
  if (!element) return

  window.dispatchEvent(new CustomEvent("cadence:overlay-opened", {detail: element}))
  positionPanel(overlay)
}

const onDocumentPointerDown = (event) => {
  const overlay = openOverlay()
  if (overlay && !overlay.contains(event.target)) close(false)
}

const onDocumentKeyDown = (event) => {
  if (event.key !== "Escape" || !openOverlayId.value) return
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
  if (!openOverlayId.value) return

  const overlay = activeOverlay()
  if (!overlay || !openOverlay()) {
    openOverlayId.value = null
    return
  }

  positionPanel(overlay)
})

onBeforeUnmount(() => {
  document.removeEventListener("pointerdown", onDocumentPointerDown)
  document.removeEventListener("keydown", onDocumentKeyDown)
  window.removeEventListener("cadence:overlay-opened", onOverlayOpened)
})
</script>

<template>
  <div ref="root" v-bind="presentation.root.attrs">
    <span v-bind="presentation.label.attrs">{{ presentation.label.text }}</span>
    <span v-bind="presentation.summary.attrs">{{ presentation.summary.text }}</span>
    <span
      v-for="badge in presentation.badges"
      :key="badge.key"
      v-bind="badge.attrs"
    >{{ badge.text }}</span>

    <slot name="open-findings-copy"></slot>

    <form v-if="presentation.review_form" v-bind="presentation.review_form.root.attrs">
      <input v-bind="presentation.review_form.payload.attrs">
      <button v-bind="presentation.review_form.button.attrs">
        <span
          :class="[
            presentation.review_form.button.icon.name,
            presentation.review_form.button.icon.class,
          ]"
        ></span>
        {{ presentation.review_form.button.text }}
      </button>
    </form>

    <slot name="preset-copy"></slot>

    <form v-if="presentation.preset_form" v-bind="presentation.preset_form.root.attrs">
      <div v-bind="presentation.preset_form.field.wrapper.attrs">
        <label v-bind="presentation.preset_form.field.label.attrs">
          <input v-bind="presentation.preset_form.field.input.attrs">
        </label>
      </div>
      <button v-bind="presentation.preset_form.button.attrs">
        <span
          :class="[
            presentation.preset_form.button.icon.name,
            presentation.preset_form.button.icon.class,
          ]"
        ></span>
        {{ presentation.preset_form.button.text }}
      </button>
    </form>

    <div
      v-if="presentation.saved_presets"
      v-bind="presentation.saved_presets.root.attrs"
      :data-overlay-open="overlayState(presentation.saved_presets).dataOverlayOpen"
    >
      <button
        v-bind="presentation.saved_presets.trigger.attrs"
        :aria-expanded="overlayState(presentation.saved_presets).ariaExpanded"
        @click="toggle(presentation.saved_presets, $event)"
      >
        <span :class="presentation.saved_presets.trigger.content.class">
          <span
            :class="[
              presentation.saved_presets.trigger.content.icon.name,
              presentation.saved_presets.trigger.content.icon.class,
            ]"
          ></span>
          {{ presentation.saved_presets.trigger.content.text }}
          <span :class="presentation.saved_presets.trigger.content.count.class">
            {{ presentation.saved_presets.trigger.content.count.text }}
          </span>
        </span>
      </button>
      <section
        v-bind="presentation.saved_presets.panel.attrs"
        :hidden="overlayState(presentation.saved_presets).hidden"
      >
        <div v-bind="presentation.saved_presets.body.attrs">
          <div
            v-for="item in presentation.saved_presets.body.items"
            :key="item.key"
            v-bind="item.root.attrs"
          >
            <div v-bind="item.row.attrs">
              <div v-bind="item.copy.root.attrs">
                <div v-bind="item.copy.name.attrs">{{ item.copy.name.text }}</div>
                <div v-bind="item.copy.summary.attrs">{{ item.copy.summary.text }}</div>
              </div>
              <div v-bind="item.actions.attrs">
                <button v-bind="item.actions.apply.attrs">
                  <span
                    :class="[item.actions.apply.icon.name, item.actions.apply.icon.class]"
                  ></span>
                  {{ item.actions.apply.text }}
                </button>
                <button v-bind="item.actions.delete.attrs">
                  <span
                    :class="[item.actions.delete.icon.name, item.actions.delete.icon.class]"
                  ></span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>

    <div
      v-if="presentation.details"
      v-bind="presentation.details.root.attrs"
      :data-overlay-open="overlayState(presentation.details).dataOverlayOpen"
    >
      <button
        v-bind="presentation.details.trigger.attrs"
        :aria-expanded="overlayState(presentation.details).ariaExpanded"
        @click="toggle(presentation.details, $event)"
      >
        <span :class="presentation.details.trigger.content.class">
          <span
            :class="[
              presentation.details.trigger.content.icon.name,
              presentation.details.trigger.content.icon.class,
            ]"
          ></span>
          {{ presentation.details.trigger.content.text }}
        </span>
      </button>
      <section
        v-bind="presentation.details.panel.attrs"
        :hidden="overlayState(presentation.details).hidden"
      >
        <div v-bind="presentation.details.body.attrs">
          <div
            v-for="group in presentation.details.body.workflow_groups"
            :key="group.key"
            v-bind="group.root.attrs"
          >
            <div v-bind="group.heading.root.attrs">
              <span v-bind="group.heading.label.attrs">{{ group.heading.label.text }}</span>
              <span v-bind="group.heading.count.attrs">{{ group.heading.count.text }}</span>
            </div>
            <ul v-bind="group.items_root.attrs">
              <li v-for="item in group.items" :key="item.key" v-bind="item.root.attrs">
                <a v-bind="item.link.attrs">{{ item.link.text }}</a>
                <span v-if="item.handled" v-bind="item.handled.attrs">
                  {{ item.handled.text }}
                </span>
                <span v-bind="item.label.attrs">{{ item.label.text }}</span>
              </li>
            </ul>
          </div>

          <div
            v-for="group in presentation.details.body.groups"
            :key="group.key"
            v-bind="group.root.attrs"
          >
            <div v-bind="group.heading.root.attrs">
              <span v-bind="group.heading.label.attrs">{{ group.heading.label.text }}</span>
              <span v-bind="group.heading.count.attrs">{{ group.heading.count.text }}</span>
            </div>
            <ul v-bind="group.items_root.attrs">
              <li v-for="item in group.items" :key="item.key" v-bind="item.root.attrs">
                <div v-bind="item.row.attrs">
                  <a v-bind="item.link.attrs">{{ item.link.text }}</a>
                  <span v-if="item.handled" v-bind="item.handled.attrs">
                    {{ item.handled.text }}
                  </span>
                  <span v-bind="item.label.attrs">{{ item.label.text }}</span>
                  <button v-for="action in item.actions" :key="action.key" v-bind="action.attrs">
                    <span :class="[action.icon.name, action.icon.class]"></span>
                  </button>
                </div>
              </li>
            </ul>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
