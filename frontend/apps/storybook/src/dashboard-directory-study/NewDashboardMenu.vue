<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";
import { directoryPath } from "./fixtures";

const items = [
  { href: `${directoryPath}/new`, icon: "hero-squares-plus", label: "New dashboard" },
  { href: `${directoryPath}/import`, icon: "hero-arrow-down-tray", label: "Import" },
] as const;
</script>

<template>
  <CadenceModalMenu side="bottom" align="end" :side-offset="4">
    <template #trigger>
      <!-- Menu triggers must be native elements; this is the primary button recipe. -->
      <button type="button" class="btn btn-primary btn-sm gap-1">
        <CadenceIcon name="hero-plus" />New<CadenceIcon name="hero-chevron-down" size="xs" />
      </button>
    </template>
    <template #content="{ open }">
      <div class="cadence-overlay-panel cadence-menu-panel">
        <div v-for="item in items" :key="item.label" class="cadence-menu-item">
          <CadenceMenuItem :active="open">
            <a :href="item.href"><CadenceIcon :name="item.icon" />{{ item.label }}</a>
          </CadenceMenuItem>
        </div>
      </div>
    </template>
  </CadenceModalMenu>
</template>
