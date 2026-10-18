<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";

/** Save dashboard, with Grafana's secondary save options in a split menu. */
defineProps<{ dirty: boolean; disabled: boolean }>();
const emit = defineEmits<{ save: []; copy: []; versions: [] }>();
</script>

<template>
  <div class="flex items-center">
    <CadenceButton
      :variant="dirty ? 'primary' : 'outline'"
      size="sm"
      :disabled="disabled"
      @click="emit('save')"
    >
      Save dashboard
    </CadenceButton>
    <CadenceModalMenu side="bottom" align="end" :side-offset="4">
      <template #trigger>
        <button type="button" class="cadence-icon-button" aria-label="More save options">
          <CadenceIcon name="hero-chevron-down" />
        </button>
      </template>
      <template #content="{ open }">
        <div class="cadence-overlay-panel cadence-menu-panel">
          <div class="cadence-menu-item">
            <CadenceMenuItem :active="open" @select="emit('copy')">
              <button type="button">
                <CadenceIcon name="hero-document-duplicate" />Save as copy
              </button>
            </CadenceMenuItem>
          </div>
          <div class="cadence-menu-item">
            <CadenceMenuItem :active="open" @select="emit('versions')">
              <button type="button"><CadenceIcon name="hero-clock" />Versions</button>
            </CadenceMenuItem>
          </div>
        </div>
      </template>
    </CadenceModalMenu>
  </div>
</template>
