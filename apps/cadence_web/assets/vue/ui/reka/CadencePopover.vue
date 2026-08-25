<script setup lang="ts">
import {PopoverContent, PopoverRoot, PopoverTrigger} from "reka-ui"
import {nextTick, onBeforeUnmount, onMounted, ref, watch} from "vue"
import {
  announceCadencePopoverOpened,
  focusCurrentPopoverTrigger,
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

const focusDiagnosticAttributes = [
  "data-popover-focus-close-handler",
  "data-popover-focus-close-suppressed",
  "data-popover-focus-after-next-tick",
  "data-popover-focus-identity-matches",
  "data-popover-focus-direct-trigger-found",
  "data-popover-focus-helper-called",
  "data-popover-focus-helper-result",
  "data-popover-focus-invoked",
  "data-popover-focus-active-id",
  "data-popover-focus-active-tag",
  "data-popover-focus-active-connected",
]

const clearFocusDiagnostics = () => {
  for (const attribute of focusDiagnosticAttributes) root.value?.removeAttribute(attribute)
}

const closeWithoutFocus = () => {
  if (!open.value) return
  suppressCloseAutoFocus = true
  open.value = false
}

const updateOpen = async (nextOpen: boolean) => {
  if (nextOpen && (!props.identity || !root.value)) return

  if (nextOpen) clearFocusDiagnostics()
  open.value = nextOpen
  if (!nextOpen) return

  await nextTick()
  if (!open.value || !root.value || root.value.id !== props.identity) {
    closeWithoutFocus()
    return
  }

  announceCadencePopoverOpened(window, root.value)
}

const restoreCurrentTriggerFocus = async () => {
  await nextTick()
  const currentRoot = root.value
  if (!currentRoot) return

  currentRoot.setAttribute("data-popover-focus-after-next-tick", "true")
  const identityMatches = currentRoot.id === props.identity
  currentRoot.setAttribute("data-popover-focus-identity-matches", String(identityMatches))
  if (!identityMatches) return

  const directTrigger = currentRoot.querySelector(":scope > [data-overlay-trigger]")
  currentRoot.setAttribute(
    "data-popover-focus-direct-trigger-found",
    String(Boolean(directTrigger)),
  )
  currentRoot.setAttribute("data-popover-focus-helper-called", "true")
  const helperResult = focusCurrentPopoverTrigger(currentRoot)
  currentRoot.setAttribute("data-popover-focus-helper-result", String(helperResult))
  currentRoot.setAttribute("data-popover-focus-invoked", String(helperResult))

  const activeElement = document.activeElement
  currentRoot.setAttribute("data-popover-focus-active-id", activeElement?.id || "")
  currentRoot.setAttribute("data-popover-focus-active-tag", activeElement?.tagName || "")
  currentRoot.setAttribute(
    "data-popover-focus-active-connected",
    String(Boolean(activeElement?.isConnected)),
  )
}

const handleCloseAutoFocus = (event: Event) => {
  const restoreFocus = !suppressCloseAutoFocus
  root.value?.setAttribute("data-popover-focus-close-handler", "true")
  root.value?.setAttribute(
    "data-popover-focus-close-suppressed",
    String(suppressCloseAutoFocus),
  )
  event.preventDefault()
  suppressCloseAutoFocus = false
  if (restoreFocus) void restoreCurrentTriggerFocus()
}

const handleInteractOutside = (event: Event) => {
  const trigger = root.value?.querySelector<HTMLElement>(":scope > [data-overlay-trigger]")
  if (event.target instanceof Node && trigger?.contains(event.target)) return
  suppressCloseAutoFocus = true
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
        @interact-outside="handleInteractOutside"
      >
        <slot name="content" :open="open"></slot>
      </PopoverContent>
      <slot v-else name="content" :open="open"></slot>
    </PopoverRoot>
  </div>
</template>
