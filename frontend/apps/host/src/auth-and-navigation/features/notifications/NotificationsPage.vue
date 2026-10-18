<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import NotificationsPanel from "./NotificationsPanel.vue";
import { readInbox, record, type Act } from "./contracts";
const props = defineProps<{
  snapshot: unknown;
  userId: unknown;
  act: Act;
  refresh: () => Promise<void>;
}>();
const crashed = ref(false);
watch(
  () => [props.snapshot, props.userId],
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const model = computed(() => {
  const value = props.snapshot;
  if (
    !record(value) ||
    value.version !== 1 ||
    value.page !== "notifications" ||
    value.status !== "ready" ||
    value.user_id !== props.userId ||
    typeof value.action_token !== "string" ||
    !/^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$/.test(value.action_token)
  )
    return null;
  try {
    return readInbox(value.data, props.userId);
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="core-notifications-page">
    <div
      v-if="crashed || !model"
      id="core-notifications-error"
      role="alert"
      class="border border-warning/40 bg-base-200 p-6"
    >
      <p>Notifications are unavailable.</p>
      <button id="core-notifications-retry" type="button" class="btn btn-sm mt-4" @click="refresh">
        Retry
      </button>
      <a id="core-notifications-reset" href="/notifications" class="btn btn-ghost btn-sm mt-4"
        >Reset filters</a
      >
    </div>
    <NotificationsPanel v-else :model="model" :act="act" :refresh="refresh" />
  </section>
</template>
