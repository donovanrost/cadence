<script setup lang="ts">
type Notification = {
  id: string
  notification_id: string
  kind: string
  title: string
  body: string | null
  unread: boolean
  action: "accept_invitation" | "mark_read" | null
  action_label: string | null
  state_label: string | null
}

defineProps<{notifications: Notification[]}>()

const emit = defineEmits<{
  "accept-invitation": [payload: {notification_id: string}]
  "mark-read": [payload: {notification_id: string}]
}>()

const payload = (notification: Notification) => ({
  notification_id: notification.notification_id
})
</script>

<template>
  <section id="notifications-panel" aria-label="Notifications">
    <div id="notifications-list" class="space-y-2" role="list">
      <article
        v-for="notification in notifications"
        :id="notification.id"
        :key="notification.notification_id"
        :data-unread="notification.unread"
        class="card border border-base-300 border-l-2 bg-base-200 transition-all"
        :class="notification.unread ? 'border-l-primary' : 'border-l-base-300'"
        role="listitem"
      >
        <div class="card-body flex flex-row items-start gap-4 p-4">
          <div class="min-w-0 flex-1">
            <p
              :id="`notification-title-${notification.notification_id}`"
              class="text-sm"
              :class="notification.unread
                ? 'font-bold text-base-content'
                : 'text-base-content/70'"
            >{{ notification.title }}</p>
            <p
              v-if="notification.body"
              :id="`notification-body-${notification.notification_id}`"
              class="mt-1 text-xs text-base-content/70"
            >{{ notification.body }}</p>
          </div>

          <div
            :id="`notification-actions-${notification.notification_id}`"
            class="flex flex-shrink-0 items-center gap-2"
          >
            <button
              v-if="notification.action === 'accept_invitation'"
              :id="`notification-accept-${notification.notification_id}`"
              type="button"
              class="btn btn-primary btn-xs"
              @click="emit('accept-invitation', payload(notification))"
            >
              {{ notification.action_label }}
            </button>

            <button
              v-else-if="notification.action === 'mark_read'"
              :id="`notification-mark-read-${notification.notification_id}`"
              type="button"
              class="btn btn-ghost btn-xs"
              @click="emit('mark-read', payload(notification))"
            >
              {{ notification.action_label }}
            </button>

            <span v-else-if="notification.state_label" class="hud-label">
              {{ notification.state_label }}
            </span>
          </div>
        </div>
      </article>
    </div>
  </section>
</template>
