<script setup>
import {onBeforeUnmount, onMounted, onUpdated, ref} from "vue"

const SNAP_WIDTH = 140
const MAX_WIDTH = 480
const MIN_CANVAS_WIDTH = 360
const COORDINATED_BREAKPOINT = 1100

const props = defineProps({
  groups: {type: Array, required: true},
  dashboard_groups: {type: Array, required: true},
  empty_state: {type: String, default: null},
  new_dashboard: {type: Object, default: null}
})

const createNavRailController = ({
  el,
  windowObject = window,
  documentObject = document,
  storage = windowObject.localStorage
}) => {
  const storageKey = el.dataset.storageKey || "cadence-ops-rail"
  let handle = null
  let expanded = false
  let width = null
  let mounted = false
  let activeDrag = null

  const readState = () => {
    const stored = storage.getItem(storageKey)
    const defaultExpanded = el.hasAttribute("data-default-expanded")
    width = null

    if (!stored) {
      expanded = defaultExpanded
      return
    }

    try {
      const parsed = JSON.parse(stored)
      expanded = parsed.state === "expanded"
      if (Number.isFinite(parsed.width)) width = parsed.width
    } catch (_error) {
      expanded = stored === "expanded"
    }
  }

  const persist = () => {
    storage.setItem(
      storageKey,
      JSON.stringify({state: expanded ? "expanded" : "collapsed", width})
    )
  }

  const apply = () => {
    if (expanded) {
      el.setAttribute("data-expanded", "")

      const peerWidth = Array.from(documentObject.querySelectorAll("[data-rail-role]"))
        .filter(rail => rail !== el)
        .reduce((total, rail) => total + rail.getBoundingClientRect().width, 0)
      const available = Math.max(
        SNAP_WIDTH,
        windowObject.innerWidth - peerWidth - MIN_CANVAS_WIDTH
      )
      const defaultWidth = el.dataset.railRole === "context" ? 288 : 224
      const preferredWidth = handle && width ? width : defaultWidth
      const appliedWidth = Math.min(preferredWidth, available, MAX_WIDTH)

      el.style.width = appliedWidth < preferredWidth || width ? `${appliedWidth}px` : ""
    } else {
      el.removeAttribute("data-expanded")
      el.style.width = ""
    }
  }

  const onViewportResize = () => apply()

  const onPeerExpanded = event => {
    if (event.detail !== el && windowObject.innerWidth < COORDINATED_BREAKPOINT && expanded) {
      expanded = false
      persist()
      apply()
    }
  }

  const onClick = event => {
    if (!event.target.closest("[data-rail-toggle]")) return

    expanded = !expanded
    persist()
    apply()

    if (expanded) {
      windowObject.dispatchEvent(
        new windowObject.CustomEvent("cadence:rail-expanded", {detail: el})
      )
    }
  }

  const finishDrag = () => {
    if (!activeDrag) return

    const {move, up, previousTransition, startWidth} = activeDrag
    windowObject.removeEventListener("pointermove", move)
    windowObject.removeEventListener("pointerup", up)
    windowObject.removeEventListener("pointercancel", up)
    el.style.transition = previousTransition

    if (!expanded && startWidth >= SNAP_WIDTH) width = Math.round(startWidth)

    activeDrag = null
    persist()
  }

  const onPointerDown = event => {
    event.preventDefault()

    try {
      handle.setPointerCapture(event.pointerId)
    } catch (_error) {
      // Synthetic events can lack an active pointer; window listeners still cover the drag.
    }

    const startX = event.clientX
    const startWidth = el.getBoundingClientRect().width
    const previousTransition = el.style.transition
    el.style.transition = "none"

    const move = moveEvent => {
      const raw = startWidth + (startX - moveEvent.clientX)
      expanded = raw >= SNAP_WIDTH

      if (expanded) width = Math.min(Math.round(raw), MAX_WIDTH)

      apply()
    }

    const up = () => finishDrag()
    activeDrag = {move, up, previousTransition, startWidth}

    windowObject.addEventListener("pointermove", move)
    windowObject.addEventListener("pointerup", up, {once: true})
    windowObject.addEventListener("pointercancel", up, {once: true})
  }

  const bindHandle = () => {
    const nextHandle = el.querySelector("[data-rail-resize]")

    if (nextHandle === handle) return
    if (handle) handle.removeEventListener("pointerdown", onPointerDown)

    handle = nextHandle
    if (handle) handle.addEventListener("pointerdown", onPointerDown)
  }

  const mount = () => {
    if (mounted) return

    mounted = true
    bindHandle()
    readState()
    apply()
    windowObject.addEventListener("resize", onViewportResize)
    windowObject.addEventListener("cadence:rail-expanded", onPeerExpanded)
    el.addEventListener("click", onClick)
  }

  const update = () => {
    bindHandle()
    apply()
  }

  const destroy = () => {
    if (!mounted) return

    if (activeDrag) finishDrag()
    if (handle) handle.removeEventListener("pointerdown", onPointerDown)
    windowObject.removeEventListener("resize", onViewportResize)
    windowObject.removeEventListener("cadence:rail-expanded", onPeerExpanded)
    el.removeEventListener("click", onClick)
    mounted = false
  }

  const state = () => ({expanded, width})

  return {mount, update, destroy, state}
}

const rail = ref(null)
let controller

onMounted(() => {
  controller = createNavRailController({el: rail.value})
  controller.mount()
})

onUpdated(() => controller?.update())

onBeforeUnmount(() => {
  controller?.destroy()
  controller = undefined
})
</script>

<template>
  <nav
    id="ops-nav-rail"
    ref="rail"
    data-storage-key="cadence-ops-rail"
    data-rail-role="navigation"
    class="group/rail w-12 data-[expanded]:w-56 shrink-0 flex flex-col border-r border-primary/20 bg-base-200 hud-grid overflow-y-auto overflow-x-hidden transition-[width] duration-150"
  >
    <button
      type="button"
      data-rail-toggle
      aria-label="Toggle navigation"
      class="h-9 shrink-0 flex items-center justify-center text-base-content/60 hover:text-base-content"
    >
      <span class="hero-bars-3 h-4 w-4 pointer-events-none"></span>
    </button>

    <div
      v-for="group in props.groups"
      :key="group.key"
      :data-ops-nav-group="group.key"
      :class="group.class"
    >
      <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">
        {{ group.label }}
      </span>
      <a
        v-for="item in group.items"
        :key="item.key"
        :href="item.href"
        :title="item.label"
        :data-ops-nav-item="item.key"
        data-phx-link="redirect"
        data-phx-link-state="push"
        :class="[
          'flex items-center gap-2 px-2 py-1.5 text-xs',
          item.active
            ? 'bg-primary/10 text-primary border-l-2 border-primary'
            : 'text-base-content/70 hover:text-base-content'
        ]"
      >
        <span :class="[item.icon, 'h-4 w-4 shrink-0']"></span>
        <span class="truncate hidden group-data-[expanded]/rail:inline">{{ item.label }}</span>
      </a>
    </div>

    <div class="mt-3 border-t border-primary/20 px-2 pt-2 space-y-1 min-h-0">
      <div
        v-for="group in props.dashboard_groups"
        :key="group.key"
        :data-ops-dashboard-nav-group="group.key"
      >
        <span class="hud-label px-1 hidden group-data-[expanded]/rail:block">
          {{ group.label }}
        </span>
        <a
          v-for="dashboard in group.items"
          :key="dashboard.dashboard_id"
          :href="dashboard.href"
          :title="dashboard.label"
          :data-ops-dashboard-nav-item="dashboard.dashboard_id"
          data-phx-link="redirect"
          data-phx-link-state="push"
          :class="[
            'flex items-center gap-2 px-2 py-1.5 text-xs truncate',
            dashboard.active
              ? 'bg-primary/10 text-primary border-l-2 border-primary'
              : 'text-base-content/70 hover:text-base-content'
          ]"
        >
          <span :class="[group.icon, 'h-3.5 w-3.5 shrink-0']"></span>
          <span class="truncate hidden group-data-[expanded]/rail:inline">
            {{ dashboard.label }}
          </span>
        </a>
      </div>

      <p
        v-if="props.empty_state"
        class="hidden px-2 py-1 text-[0.6875rem] leading-4 text-base-content/45 group-data-[expanded]/rail:block"
      >
        {{ props.empty_state }}
      </p>

      <a
        v-if="props.new_dashboard"
        :href="props.new_dashboard.href"
        :title="props.new_dashboard.title"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="flex items-center gap-2 px-2 py-1.5 text-xs text-base-content/60 hover:text-primary"
      >
        <span :class="[props.new_dashboard.icon, 'h-3.5 w-3.5 shrink-0']"></span>
        <span class="hidden group-data-[expanded]/rail:inline">
          {{ props.new_dashboard.label }}
        </span>
      </a>
    </div>
  </nav>
</template>
