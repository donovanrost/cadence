<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";

defineProps<{ id: string; title: string; editing: boolean; inspectable: boolean }>();
const emit = defineEmits<{ inspect: []; configure: []; remove: [] }>();
</script>

<template>
  <CadenceModalMenu side="bottom" align="end" :side-offset="4">
    <template #trigger>
      <!-- Menu triggers must be native elements; this uses the icon-button recipe. -->
      <button
        :id="`${id}-trigger`"
        type="button"
        class="cadence-icon-button"
        :aria-label="`Actions for ${title}`"
      >
        <CadenceIcon name="hero-ellipsis-vertical" />
      </button>
    </template>
    <template #content="{ open }">
      <div :id="id" class="cadence-overlay-panel cadence-menu-panel">
        <div v-if="inspectable" class="cadence-menu-item">
          <CadenceMenuItem :active="open" @select="emit('inspect')">
            <button type="button"><CadenceIcon name="hero-table-cells" />Inspect data</button>
          </CadenceMenuItem>
        </div>
        <template v-if="editing">
          <div class="cadence-menu-item">
            <CadenceMenuItem :active="open" @select="emit('configure')">
              <button type="button"><CadenceIcon name="hero-cog-6-tooth" />Configure</button>
            </CadenceMenuItem>
          </div>
          <div class="cadence-menu-item">
            <CadenceMenuItem :active="open" @select="emit('remove')">
              <button type="button" class="text-error">
                <CadenceIcon name="hero-trash" />Remove
              </button>
            </CadenceMenuItem>
          </div>
        </template>
        <p v-if="!inspectable && !editing" class="px-3 py-1.5 text-xs text-base-content/60">
          No actions
        </p>
      </div>
    </template>
  </CadenceModalMenu>
</template>
