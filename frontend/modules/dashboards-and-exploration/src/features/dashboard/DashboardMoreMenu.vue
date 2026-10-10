<script setup lang="ts">
import type { IconName } from "@cadence/ui/icons";
import { computed } from "vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";

const props = defineProps<{ base: string; author: boolean; diagnosticsHref: string | null }>();
const emit = defineEmits<{ versions: [] }>();
type Link = { href: string | null; icon: IconName; label: string; show: boolean };
const ops = computed(() => props.base.replace(/\/dashboards\/[^/]+$/, ""));
const links = computed(() => {
  const all: Link[] = [
    {
      href: `${props.base}/activity`,
      icon: "hero-clock",
      label: "Activity log",
      show: true,
    },
    {
      href: `${props.base}/settings`,
      icon: "hero-cog-6-tooth",
      label: "Settings & sharing",
      show: props.author,
    },
    {
      href: props.diagnosticsHref,
      icon: "hero-wrench-screwdriver",
      label: "Execution diagnostics",
      show: true,
    },
    {
      href: `${ops.value}/explore`,
      icon: "hero-magnifying-glass",
      label: "Explore telemetry",
      show: true,
    },
  ];
  return all.flatMap((link) =>
    link.show && link.href !== null ? [{ ...link, href: link.href }] : [],
  );
});
</script>

<template>
  <CadenceModalMenu side="bottom" align="end" :side-offset="4">
    <template #trigger>
      <!-- Menu triggers must be native elements; this uses the icon-button recipe. -->
      <button
        id="dashboard-more-trigger"
        type="button"
        class="cadence-icon-button"
        aria-label="More dashboard actions"
      >
        <CadenceIcon name="hero-ellipsis-horizontal" />
      </button>
    </template>
    <template #content="{ open }">
      <div id="dashboard-more-menu" class="cadence-overlay-panel cadence-menu-panel">
        <div class="cadence-menu-item">
          <CadenceMenuItem :active="open" @select="emit('versions')">
            <button type="button"><CadenceIcon name="hero-clock" />Versions</button>
          </CadenceMenuItem>
        </div>
        <div v-for="link in links" :key="link.label" class="cadence-menu-item">
          <CadenceMenuItem :active="open">
            <a :href="link.href"><CadenceIcon :name="link.icon" />{{ link.label }}</a>
          </CadenceMenuItem>
        </div>
      </div>
    </template>
  </CadenceModalMenu>
</template>
