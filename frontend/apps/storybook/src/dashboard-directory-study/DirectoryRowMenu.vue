<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";
import { dashboardPath, type StudyDashboard } from "./fixtures";

defineProps<{ dashboard: StudyDashboard }>();
const emit = defineEmits<{ duplicate: []; archive: []; restore: [] }>();
</script>

<template>
  <CadenceModalMenu side="bottom" align="end" :side-offset="4">
    <template #trigger>
      <button
        type="button"
        class="cadence-icon-button"
        :aria-label="`Actions for ${dashboard.name}`"
      >
        <CadenceIcon name="hero-ellipsis-horizontal" />
      </button>
    </template>
    <template #content="{ open }">
      <div class="cadence-overlay-panel cadence-menu-panel">
        <div class="cadence-menu-item">
          <CadenceMenuItem :active="open" @select="emit('duplicate')">
            <button type="button"><CadenceIcon name="hero-document-duplicate" />Duplicate</button>
          </CadenceMenuItem>
        </div>
        <div class="cadence-menu-item">
          <CadenceMenuItem :active="open">
            <a :href="`${dashboardPath(dashboard.id)}/settings`"
              ><CadenceIcon name="hero-cog-6-tooth" />Settings &amp; sharing</a
            >
          </CadenceMenuItem>
        </div>
        <div class="cadence-menu-item">
          <CadenceMenuItem v-if="dashboard.archived" :active="open" @select="emit('restore')">
            <button type="button"><CadenceIcon name="hero-arrow-uturn-left" />Restore</button>
          </CadenceMenuItem>
          <CadenceMenuItem v-else :active="open" @select="emit('archive')">
            <button type="button" class="text-error">
              <CadenceIcon name="hero-archive-box" />Archive
            </button>
          </CadenceMenuItem>
        </div>
      </div>
    </template>
  </CadenceModalMenu>
</template>
