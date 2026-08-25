<script setup lang="ts">
import {PopoverContent, PopoverRoot, PopoverTrigger} from "reka-ui"
import {nextTick, onBeforeUnmount, onMounted, ref, watch} from "vue"
import {
  announceCadencePopoverOpened,
  preservesPopoverOpenState,
  subscribeToLegacyOverlayOpen,
} from "./popover_compatibility.js"

defineOptions({inheritAttrs: false})

type PopoverIdentity = string | null | undefined

const props = withDefaults(
  defineProps<{
    identity: PopoverIdentity
    side?: "top" | "right" | "bottom" | "left"
    align?: "start" | "center" | "end"
    sideOffset?: number
    collisionPadding?: number
  }>(),
  {
    side: "bottom",
    align: "end",
    sideOffset: 8,
    collisionPadding: 16,
  },
)

const root = ref<HTMLElement | null>(null)
const open = ref(false)
let suppressCloseAutoFocus = false
let removeLegacyOverlayListener: (() => void) | null = null

const closeWithoutFocus = () => {
  if (!open.value) return
  suppressCloseAutoFocus = true
  open.value = false
}

const updateOpen = async (nextOpen: boolean) => {
  if (nextOpen && (!props.identity || !root.value)) return

  open.value = nextOpen
  if (!nextOpen) return

  await nextTick()
  if (!open.value || !root.value || root.value.id !== props.identity) {
    closeWithoutFocus()
    return
  }

  announceCadencePopoverOpened(window, root.value)
}

const handleCloseAutoFocus = (event: Event) => {
  if (!suppressCloseAutoFocus) return
  event.preventDefault()
  suppressCloseAutoFocus = false
}

watch(
  () => props.identity,
  (nextIdentity, previousIdentity) => {
    if (!preservesPopoverOpenState(open.value, previousIdentity, nextIdentity)) {
      closeWithoutFocus()
    }
  },
)

onMounted(() => {
  if (!root.value) return
  removeLegacyOverlayListener = subscribeToLegacyOverlayOpen(
    window,
    root.value,
    closeWithoutFocus,
  )
})

onBeforeUnmount(() => {
  suppressCloseAutoFocus = true
  open.value = false
  removeLegacyOverlayListener?.()
  removeLegacyOverlayListener = null
})
</script>

<template>
  <div
    ref="root"
    v-bind="$attrs"
    :data-overlay-open="open ? '' : undefined"
  >
    <PopoverRoot
      :open="open"
      :modal="false"
      @update:open="updateOpen"
    >
      <PopoverTrigger as-child>
        <slot name="trigger" :open="open"></slot>
      </PopoverTrigger>

      <PopoverContent
        v-if="open"
        as-child
        :side="props.side"
        :align="props.align"
        :side-offset="props.sideOffset"
        :collision-padding="props.collisionPadding"
        position-strategy="fixed"
        @close-auto-focus="handleCloseAutoFocus"
      >
        <slot name="content" :open="open"></slot>
      </PopoverContent>
      <slot v-else name="content" :open="open"></slot>
    </PopoverRoot>
  </div>
</template>
