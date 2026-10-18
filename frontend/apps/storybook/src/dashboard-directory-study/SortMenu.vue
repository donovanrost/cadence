<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";
import { sortLabels, type Sort } from "./state";

defineProps<{ sort: Sort }>();
const emit = defineEmits<{ change: [sort: Sort] }>();
const sorts = Object.keys(sortLabels) as Sort[];
</script>

<template>
  <CadenceModalMenu side="bottom" align="end" :side-offset="4">
    <template #trigger>
      <button type="button" class="btn btn-ghost btn-sm gap-1" aria-label="Sort dashboards">
        <CadenceIcon name="hero-bars-arrow-down" />{{ sortLabels[sort] }}
        <CadenceIcon name="hero-chevron-down" size="xs" />
      </button>
    </template>
    <template #content="{ open }">
      <div class="cadence-overlay-panel cadence-menu-panel">
        <div v-for="option in sorts" :key="option" class="cadence-menu-item">
          <CadenceMenuItem :active="open" @select="emit('change', option)">
            <button type="button" :aria-pressed="option === sort">
              <CadenceIcon :name="option === sort ? 'hero-check' : 'hero-minus'" />
              {{ sortLabels[option] }}
            </button>
          </CadenceMenuItem>
        </div>
      </div>
    </template>
  </CadenceModalMenu>
</template>
