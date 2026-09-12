<script setup lang="ts">
import { computed } from "vue";
import { present, record } from "../../shared/contracts";
import { readBell } from "./bell-contract";
import NotificationBell from "./NotificationBell.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ context?: unknown; expectedUserId?: unknown }>();
const context = computed(() => {
  const value = props.context;
  return present(props.expectedUserId, 512) &&
    record(value) &&
    record(value.user) &&
    value.user.user_id === props.expectedUserId &&
    readBell(value)
    ? value
    : null;
});
</script>
<template>
  <NotificationBell id="notifications-bell-application" :context="context" />
</template>
