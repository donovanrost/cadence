<script setup>
import {onBeforeUnmount, onMounted, onUpdated, ref} from "vue"
import {createNavRailController} from "./hooks/nav_rail_controller.js"

const props = defineProps({
  groups: {type: Array, required: true},
  dashboard_groups: {type: Array, required: true},
  empty_state: {type: String, default: null},
  new_dashboard: {type: Object, default: null}
})

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
