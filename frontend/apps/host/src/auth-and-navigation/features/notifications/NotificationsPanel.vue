<script setup lang="ts">
import { nextTick, ref } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import {
  inboxHref,
  readActionResult,
  type Inbox,
  type Notification,
  type Action,
  type Act,
} from "./contracts";
const props = defineProps<{ model: Inbox; act: Act; refresh: () => Promise<void> }>();
const busy = ref(false);
const uncertain = ref(false);
const message = ref("");
async function perform(action: Action, row: Notification) {
  if (busy.value || uncertain.value) return;
  busy.value = true;
  message.value = "";
  try {
    const result = readActionResult(await props.act(action, { notification_id: row.id }));
    message.value =
      result === "unavailable"
        ? "This action is no longer available. Refresh to review the current notification."
        : result === "read"
          ? "Notification marked read."
          : "Invitation accepted.";
  } catch {
    uncertain.value = true;
    message.value = "The action outcome could not be confirmed. Refresh before trying again.";
  } finally {
    busy.value = false;
  }
}
async function refreshPage() {
  if (busy.value) return;
  busy.value = true;
  const previous = props.model.observed_at;
  try {
    await props.refresh();
    await nextTick();
    if (props.model.observed_at === previous) throw Error("No fresh observation");
    uncertain.value = false;
    message.value = "Notifications refreshed.";
  } catch {
    message.value = "Refresh failed. These notifications are from the previous observation.";
  } finally {
    busy.value = false;
  }
}
const state = (row: Notification) =>
  ({
    pending: "Invitation pending",
    accepted: "Invitation accepted",
    revoked: "Invitation revoked",
    expired: "Invitation expired",
    unavailable: "Invitation unavailable",
    none: row.read_at ? "Read" : "Unread",
  })[row.invitation_status];
</script>
<template>
  <section id="notifications-page" class="mx-auto max-w-4xl space-y-6">
    <CadencePageHeading>
      <template #title>Notifications</template>
      <template #description
        >Invitations, access grants, and system notices for your account.</template
      >
      <template #actions
        ><button
          id="refresh-notifications"
          type="button"
          class="btn btn-sm"
          :disabled="busy"
          @click="refreshPage"
        >
          Refresh
        </button></template
      >
    </CadencePageHeading>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <nav aria-label="Notification filter" class="flex gap-3">
        <a
          id="notifications-all"
          href="/notifications"
          class="btn btn-sm"
          :aria-current="model.query.unread === '' ? 'page' : undefined"
          >All</a
        >
        <a
          id="notifications-unread"
          href="/notifications?unread=true"
          class="btn btn-sm"
          :aria-current="model.query.unread === 'true' ? 'page' : undefined"
          >Unread</a
        >
      </nav>
      <p class="text-xs text-base-content/65">Up to {{ model.limit }} notifications per page.</p>
    </div>
    <p v-if="message" id="notification-action-message" role="status" class="text-sm">
      {{ message }}
    </p>
    <p
      v-if="model.notifications.length === 0"
      id="notifications-empty-state"
      class="border border-dashed border-base-300 p-8 text-center text-base-content/70"
    >
      {{
        model.query.unread
          ? "No unread notifications on this page."
          : "No notifications on this page."
      }}
    </p>
    <section v-else id="notifications-panel" aria-label="Notifications">
      <div id="notifications-list" role="list" class="space-y-3">
        <article
          v-for="row in model.notifications"
          :id="`notification-${row.id}`"
          :key="row.id"
          :data-unread="row.read_at === null"
          role="listitem"
          class="min-w-0 border border-base-300 border-l-2 bg-base-200 p-4"
          :class="row.read_at ? 'border-l-base-300' : 'border-l-primary'"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <h2 :id="`notification-title-${row.id}`" class="min-w-0 break-words text-sm font-bold">
              {{ row.title }}
            </h2>
            <span class="text-xs text-base-content/70">{{ row.read_at ? "Read" : "Unread" }}</span>
          </div>
          <p
            v-if="row.body"
            :id="`notification-body-${row.id}`"
            class="mt-2 whitespace-pre-wrap break-words text-sm text-base-content/75"
          >
            {{ row.body }}
          </p>
          <div class="mt-3 flex flex-wrap items-center gap-3">
            <p :id="`notification-state-${row.id}`" class="text-xs">{{ state(row) }}</p>
            <time :datetime="row.created_at" class="break-all text-xs text-base-content/60">{{
              row.created_at
            }}</time>
          </div>
          <div :id="`notification-actions-${row.id}`" class="mt-3 flex flex-wrap gap-2">
            <button
              v-if="row.invitation_status === 'pending'"
              :id="`notification-accept-${row.id}`"
              type="button"
              class="btn btn-primary btn-sm"
              :disabled="busy || uncertain"
              @click="perform('accept_invitation', row)"
            >
              Accept invitation
            </button>
            <button
              v-if="row.read_at === null"
              :id="`notification-mark-read-${row.id}`"
              type="button"
              class="btn btn-ghost btn-sm"
              :disabled="busy || uncertain"
              @click="perform('mark_notification_read', row)"
            >
              Mark read
            </button>
          </div>
        </article>
      </div>
    </section>
    <nav aria-label="Notification history" class="flex flex-wrap gap-3">
      <a
        v-if="model.query.before_at"
        id="notifications-newest"
        :href="inboxHref({ unread: model.query.unread })"
        class="btn btn-sm"
        >Newest notifications</a
      >
      <a
        v-if="model.next_cursor"
        id="notifications-older"
        :href="
          inboxHref({
            unread: model.query.unread,
            before_at: model.next_cursor.at,
            before_id: model.next_cursor.id,
          })
        "
        class="btn btn-sm"
        >Older notifications</a
      >
    </nav>
    <p class="break-all text-xs text-base-content/60">
      Observed
      <time id="notifications-observed-at" :datetime="model.observed_at">{{
        model.observed_at
      }}</time>
    </p>
  </section>
</template>
