<script setup lang="ts">
import { computed } from "vue";

import CadenceMenu from "./ui/reka/CadenceMenu.vue";
import CadenceMenuItem from "./ui/reka/CadenceMenuItem.vue";

type AttrValue = string | boolean | null;
type Attrs = Record<string, AttrValue>;

type MenuPresentation = {
  root: { attrs: Attrs };
  trigger: { attrs: Attrs; icon_class: string };
  panel: {
    attrs: Attrs;
    items: Array<{
      key: string;
      wrapper: { attrs: Attrs };
      link: {
        attrs: Attrs;
        icon_class: string;
        text: string;
        badge: { class: string; attrs: Attrs; text: string } | null;
      };
    }>;
  };
};

const props = defineProps<{ presentation: MenuPresentation }>();

const menuIdentity = computed(() => {
  const identity = props.presentation.root.attrs.id;
  return typeof identity === "string" ? identity : null;
});

const panelAttrs = computed(() => {
  const attrs = { ...props.presentation.panel.attrs };
  delete attrs.hidden;
  return attrs;
});
</script>

<template>
  <CadenceMenu
    :identity="menuIdentity"
    side="bottom"
    align="end"
    :collision-padding="16"
    v-bind="props.presentation.root.attrs"
  >
    <template #trigger="{ open }">
      <button v-bind="props.presentation.trigger.attrs" :aria-expanded="String(open)">
        <span :class="props.presentation.trigger.icon_class"></span>
      </button>
    </template>

    <template #content="{ open, onItemSelect }">
      <div v-bind="panelAttrs" :hidden="!open">
        <div
          v-for="item in props.presentation.panel.items"
          :key="item.key"
          v-bind="item.wrapper.attrs"
        >
          <CadenceMenuItem :active="open" @select="onItemSelect">
            <a v-bind="item.link.attrs">
              <span :class="item.link.icon_class"></span>
              {{ item.link.text }}
              <span
                v-if="item.link.badge"
                :class="item.link.badge.class"
                v-bind="item.link.badge.attrs"
              >
                {{ item.link.badge.text }}
              </span>
            </a>
          </CadenceMenuItem>
        </div>
      </div>
    </template>
  </CadenceMenu>
</template>
