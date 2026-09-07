<script setup lang="ts">
import AccountDropdownMenu from "@cadence/ui/AccountDropdownMenu.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
type Notification = {
  notification_id: string;
  title: string;
  body: string | null;
  unread: boolean;
};
defineProps<{ count: number; notifications: Notification[] }>();
const emit = defineEmits<{ "mark-read": [params: { notification_id: string }] }>();
function select(event: MouseEvent, notification: Notification) {
  if (notification.unread) {
    event.preventDefault();
    emit("mark-read", { notification_id: notification.notification_id });
  }
}
</script>
<template>
  <AccountDropdownMenu class="dropdown dropdown-end">
    <template #trigger="{ open }"
      ><button
        id="notifications-bell-application"
        type="button"
        aria-label="Notifications"
        :aria-expanded="open"
        class="btn btn-ghost btn-sm btn-circle relative"
      >
        <span class="hero-bell h-5 w-5"></span
        ><span
          v-if="count"
          class="badge badge-primary badge-xs absolute -top-0.5 -right-0.5 font-mono"
          >{{ count > 9 ? "9+" : count }}</span
        >
      </button></template
    >
    <template #content="{ open, onItemSelect }"
      ><div
        role="menu"
        class="dropdown-content menu bg-base-200 z-[var(--z-popover)] w-80 p-2 shadow-lg border border-primary/20 max-h-96 overflow-y-auto"
      >
        <p class="hud-label px-3 py-2">
          Notifications <span v-if="count" class="text-primary">({{ count }} unread)</span>
        </p>
        <p v-if="!notifications.length" class="px-3 py-4 text-center text-sm text-base-content/60">
          No notifications
        </p>
        <CadenceMenuItem
          v-for="notification in notifications"
          :key="notification.notification_id"
          :active="open"
          @select="onItemSelect"
          ><a
            href="/notifications"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="flex items-start gap-2 px-3 py-2"
            @click="select($event, notification)"
            ><span
              v-if="notification.unread"
              class="mt-1.5 w-1.5 h-1.5 rounded-full bg-primary shrink-0"
            ></span
            ><span class="min-w-0"
              ><span class="block text-xs font-semibold truncate">{{ notification.title }}</span
              ><span v-if="notification.body" class="block text-xs text-base-content/70 truncate">{{
                notification.body
              }}</span></span
            ></a
          ></CadenceMenuItem
        >
        <CadenceMenuItem :active="open" @select="onItemSelect"
          ><a
            href="/notifications"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="border-t border-primary/10 mt-1 pt-2 text-xs text-primary uppercase tracking-wide"
            >See all notifications</a
          ></CadenceMenuItem
        >
      </div></template
    >
  </AccountDropdownMenu>
</template>
