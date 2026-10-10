<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";
import type { MenuAction } from "@cadence/plugin-sdk/page-header";

withDefaults(
  defineProps<{
    action: MenuAction;
    primary: boolean;
    run: (id: string, command: () => void | Promise<void>) => Promise<void>;
    iconOnly?: boolean;
  }>(),
  { iconOnly: false },
);
</script>

<template>
  <CadenceModalMenu side="bottom" align="end" :side-offset="4">
    <template #trigger>
      <!-- Menu triggers must be native elements; these are the button recipes. -->
      <button
        v-if="iconOnly"
        :id="`host-action-${action.id}`"
        type="button"
        class="cadence-icon-button"
        :aria-label="action.label"
      >
        <CadenceIcon name="hero-ellipsis-horizontal" />
      </button>
      <button
        v-else
        :id="`host-action-${action.id}`"
        type="button"
        class="btn btn-sm gap-1"
        :class="primary ? 'btn-primary' : 'btn-ghost'"
        :disabled="action.disabled === true"
      >
        <CadenceIcon v-if="action.icon" :name="action.icon" />{{ action.label }}
        <CadenceIcon name="hero-chevron-down" size="xs" />
      </button>
    </template>
    <template #content="{ open }">
      <div class="cadence-overlay-panel cadence-menu-panel">
        <div v-for="item in action.menu" :key="item.id" class="cadence-menu-item">
          <CadenceMenuItem
            :active="open"
            :disabled="item.disabled === true"
            @select="'run' in item && run(item.id, item.run)"
          >
            <a
              v-if="'href' in item"
              :href="item.href"
              :class="item.tone === 'danger' ? 'text-error' : ''"
            >
              <CadenceIcon v-if="item.icon" :name="item.icon" />{{ item.label }}
            </a>
            <button v-else type="button" :class="item.tone === 'danger' ? 'text-error' : ''">
              <CadenceIcon v-if="item.icon" :name="item.icon" />{{ item.label }}
            </button>
          </CadenceMenuItem>
        </div>
      </div>
    </template>
  </CadenceModalMenu>
</template>
