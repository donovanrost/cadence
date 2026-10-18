<script setup lang="ts">
import { onBeforeUnmount, onMounted, onUpdated, ref } from "vue";
import type { contextRail, contextSections } from "./context";
import { createNavRailController } from "./nav_rail_controller";

const props = defineProps<{
  rail: typeof contextRail;
  sections: ReturnType<typeof contextSections>;
}>();

const railElement = ref<HTMLElement | null>(null);
let controller: ReturnType<typeof createNavRailController> | undefined;

onMounted(() => {
  if (!railElement.value) return;
  controller = createNavRailController({ el: railElement.value });
  controller.mount();
});

onUpdated(() => controller?.update());

onBeforeUnmount(() => {
  controller?.destroy();
  controller = undefined;
});
</script>

<template>
  <aside
    :id="props.rail.id"
    ref="railElement"
    :aria-label="props.rail.aria_label"
    data-ops-context-rail
    :data-storage-key="props.rail.storage_key"
    :data-rail-role="props.rail.role"
    :data-default-expanded="props.rail.default_expanded ? '' : null"
    class="group/ctx relative w-12 data-[expanded]:w-72 shrink-0 flex flex-col border-l border-primary/20 bg-base-200 hud-grid overflow-hidden transition-[width] duration-150"
  >
    <div
      data-rail-resize
      :title="props.rail.resize_title"
      class="absolute inset-y-0 left-0 z-10 w-1.5 cursor-col-resize touch-none hover:bg-primary/40 active:bg-primary/60 hidden group-data-[expanded]/ctx:block"
    ></div>
    <button
      :id="`${props.rail.id}-toggle`"
      type="button"
      data-rail-toggle
      data-ops-context-rail-toggle
      :aria-label="props.rail.toggle_label"
      class="h-9 shrink-0 flex items-center justify-center text-base-content/60 hover:text-base-content"
    >
      <span
        class="hero-chevron-double-right h-4 w-4 pointer-events-none hidden group-data-[expanded]/ctx:inline"
      ></span>
      <span
        class="hero-chevron-double-left h-4 w-4 pointer-events-none group-data-[expanded]/ctx:hidden"
      ></span>
    </button>

    <div
      class="flex flex-col items-stretch gap-1 pt-1 overflow-y-auto group-data-[expanded]/ctx:hidden"
    >
      <button
        v-for="section in props.sections"
        :key="`collapsed-${section.key}`"
        type="button"
        data-rail-toggle
        :data-ops-context-collapsed-section="section.key"
        :data-ops-context-section-status="section.status"
        :data-ops-context-section-count="section.count"
        :title="section.title"
        class="flex flex-col items-center gap-1 py-2 text-base-content/60 hover:text-base-content hover:bg-base-300/40"
      >
        <span :class="[section.icon, 'h-4 w-4 pointer-events-none']"></span>
        <span
          :class="['h-1.5 w-1.5 rounded-full pointer-events-none', section.status_dot_class]"
        ></span>
        <span
          v-if="section.count !== null"
          class="font-mono text-[0.625rem] leading-none pointer-events-none"
        >
          {{ section.count }}
        </span>
      </button>
    </div>

    <div class="hidden group-data-[expanded]/ctx:flex flex-col min-h-0 flex-1 overflow-y-auto">
      <section
        v-for="section in props.sections"
        :key="section.key"
        :data-ops-context-section="section.key"
        :data-ops-context-section-status="section.status"
        :data-ops-context-section-count="section.count"
        class="border-b border-base-300/60"
      >
        <header class="flex items-center gap-2 px-2 pt-2">
          <span :class="[section.icon, 'h-3.5 w-3.5 text-base-content/60']"></span>
          <span class="hud-label">{{ section.title }}</span>
          <span :class="['ml-auto h-2 w-2 rounded-full', section.status_dot_class]"></span>
        </header>

        <div :data-ops-context-module-freshness="section.freshness" class="px-2 py-2">
          <div v-if="section.content.kind === 'alarms'" class="space-y-2 text-xs">
            <div v-if="section.content.active" class="flex flex-wrap gap-1.5">
              <span
                v-for="badge in section.content.badges"
                :key="badge.label"
                :class="[
                  'inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium',
                  badge.class,
                ]"
              >
                <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
                <span v-if="badge.count !== null" class="font-mono">{{ badge.count }}</span>
                <span class="uppercase text-[0.65rem]">{{ badge.label }}</span>
              </span>
            </div>
            <div v-else class="flex items-center gap-2 text-base-content/55">
              <span class="h-1.5 w-1.5 rounded-full bg-success"></span>
              {{ section.content.empty_label }}
            </div>
            <p
              v-if="section.content.latest_transition_label"
              class="font-mono text-[0.65rem] text-base-content/50"
            >
              {{ section.content.latest_transition_label }}
            </p>
          </div>

          <div v-else-if="section.content.kind === 'commands'" class="space-y-2 text-xs">
            <div class="grid grid-cols-2 gap-1">
              <div
                v-for="count in section.content.counts"
                :key="count.label"
                class="flex items-center justify-between gap-2 border border-base-300/50 bg-base-100/35 px-2 py-1"
              >
                <span class="text-[0.65rem] text-base-content/55">{{ count.label }}</span>
                <span :class="['font-mono text-xs font-semibold', count.class]">
                  {{ count.value }}
                </span>
              </div>
            </div>
            <div
              v-if="section.content.followed_command"
              :data-ops-context-followed-command="
                section.content.followed_command.command_request_id
              "
              class="border-l-2 border-info bg-info/10 px-2 py-1.5"
            >
              <p class="hud-label text-info">Following</p>
              <p class="mt-0.5 truncate font-semibold">
                {{ section.content.followed_command.command_name }}
              </p>
              <p class="truncate font-mono text-[0.65rem] text-base-content/55">
                {{ section.content.followed_command.detail }}
              </p>
            </div>
          </div>

          <template v-else-if="section.content.kind === 'fleet_health'">
            <div v-if="section.content.available" class="flex flex-wrap items-center gap-2 text-xs">
              <span
                v-for="badge in section.content.badges"
                :key="badge.label"
                :class="[
                  'inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium',
                  badge.class,
                ]"
              >
                <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
                <span v-if="badge.count !== null" class="font-mono">{{ badge.count }}</span>
                <span class="uppercase text-[0.65rem]">{{ badge.label }}</span>
              </span>
              <span class="font-mono text-xs text-base-content/60 basis-full">
                {{ section.content.violating_points_label }}
              </span>
            </div>
            <p v-else class="text-xs text-base-content/60">
              {{ section.content.unavailable_label }}
            </p>
          </template>

          <div
            class="mt-1 flex items-center justify-between gap-2 border-t border-base-300/50 pt-1.5"
          >
            <span class="font-mono text-[0.625rem] uppercase tracking-wide text-base-content/45">
              {{ section.freshness_label }} · {{ section.observed_at_label }}
            </span>
            <a
              :href="section.destination"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="inline-flex items-center gap-1 text-[0.65rem] font-semibold text-primary hover:underline"
            >
              Open <span class="hero-arrow-up-right h-3 w-3"></span>
            </a>
          </div>
        </div>
      </section>
    </div>
  </aside>
</template>
