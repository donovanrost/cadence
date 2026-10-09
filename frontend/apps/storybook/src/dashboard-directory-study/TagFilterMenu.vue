<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";

defineProps<{ tags: readonly string[]; selected: readonly string[] }>();
const emit = defineEmits<{ toggle: [tag: string] }>();

// Keep the menu open so several tags can be chosen in one visit.
function choose(event: Event, tag: string) {
  event.preventDefault();
  emit("toggle", tag);
}
</script>

<template>
  <CadenceModalMenu side="bottom" align="start" :side-offset="4">
    <template #trigger>
      <button
        type="button"
        class="btn btn-sm gap-1"
        :aria-label="`Filter by tag, ${selected.length} selected`"
      >
        <CadenceIcon name="hero-tag" />Tags
        <span v-if="selected.length" class="font-mono text-xs text-primary">{{
          selected.length
        }}</span>
        <CadenceIcon name="hero-chevron-down" size="xs" />
      </button>
    </template>
    <template #content="{ open }">
      <div class="cadence-overlay-panel cadence-menu-panel max-h-80 overflow-y-auto">
        <div v-for="tag in tags" :key="tag" class="cadence-menu-item">
          <CadenceMenuItem :active="open" @select="choose($event, tag)">
            <button type="button" :aria-pressed="selected.includes(tag)">
              <CadenceIcon :name="selected.includes(tag) ? 'hero-check' : 'hero-tag'" />{{ tag }}
            </button>
          </CadenceMenuItem>
        </div>
      </div>
    </template>
  </CadenceModalMenu>
</template>
