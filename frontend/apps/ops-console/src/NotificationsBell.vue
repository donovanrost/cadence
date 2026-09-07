<script setup lang="ts">
import AccountDropdownMenu from "@cadence/ui/AccountDropdownMenu.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";

type Attributes = Record<string, string>;

type TextPresentation = {
  class: string;
  text: string | null;
};

type NotificationPresentation = {
  key: string;
  link: { class: string; attrs: Attributes };
  dot_class: string | null;
  content_class: string;
  title: TextPresentation;
  body: TextPresentation | null;
};

type Presentation = {
  root: { class: string };
  trigger: {
    class: string;
    attrs: Attributes;
    icon_class: string;
    badge: TextPresentation | null;
  };
  menu: {
    id: string;
    class: string;
    attrs: Attributes;
    title: {
      item_class: string;
      label_class: string;
      label: string;
      unread_class: string;
      unread_label: string | null;
    };
    empty_state: { class: string; label: string } | null;
    notifications: NotificationPresentation[];
    footer: {
      item_class: string;
      class: string;
      attrs: Attributes;
      label: string;
    };
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <AccountDropdownMenu :class="presentation.root.class">
    <template #trigger="{ open }">
      <button
        :class="presentation.trigger.class"
        v-bind="presentation.trigger.attrs"
        :aria-expanded="open"
      >
        <span :class="presentation.trigger.icon_class"></span>
        <span v-if="presentation.trigger.badge" :class="presentation.trigger.badge.class">{{
          presentation.trigger.badge.text
        }}</span>
      </button>
    </template>

    <template #content="{ open, onItemSelect }">
      <div
        :id="presentation.menu.id"
        :class="presentation.menu.class"
        v-bind="presentation.menu.attrs"
      >
        <li :class="presentation.menu.title.item_class">
          <span :class="presentation.menu.title.label_class">
            {{ presentation.menu.title.label }}
            <span
              v-if="presentation.menu.title.unread_label"
              :class="presentation.menu.title.unread_class"
              >{{ presentation.menu.title.unread_label }}</span
            >
          </span>
        </li>

        <li v-if="presentation.menu.empty_state" :class="presentation.menu.empty_state.class">
          {{ presentation.menu.empty_state.label }}
        </li>
        <template v-else>
          <li v-for="notification in presentation.menu.notifications" :key="notification.key">
            <CadenceMenuItem :active="open" @select="onItemSelect">
              <a :class="notification.link.class" v-bind="notification.link.attrs">
                <span v-if="notification.dot_class" :class="notification.dot_class"></span>
                <span :class="notification.content_class">
                  <span :class="notification.title.class">{{ notification.title.text }}</span>
                  <span v-if="notification.body" :class="notification.body.class">
                    {{ notification.body.text }}
                  </span>
                </span>
              </a>
            </CadenceMenuItem>
          </li>
        </template>

        <li :class="presentation.menu.footer.item_class">
          <CadenceMenuItem :active="open" @select="onItemSelect">
            <a :class="presentation.menu.footer.class" v-bind="presentation.menu.footer.attrs">
              {{ presentation.menu.footer.label }}
            </a>
          </CadenceMenuItem>
        </li>
      </div>
    </template>
  </AccountDropdownMenu>
</template>
