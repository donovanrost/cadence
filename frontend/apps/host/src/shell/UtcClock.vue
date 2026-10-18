<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";

const utcTime = ref("");
let timerId: ReturnType<typeof setInterval> | undefined;

const pad = (value: number) => String(value).padStart(2, "0");

const updateUtcTime = () => {
  const now = new Date();

  utcTime.value = `${pad(now.getUTCHours())}:${pad(now.getUTCMinutes())}:${pad(now.getUTCSeconds())} UTC`;
};

onMounted(() => {
  updateUtcTime();
  timerId = setInterval(updateUtcTime, 1000);
});

onUnmounted(() => {
  if (timerId !== undefined) clearInterval(timerId);
});
</script>

<template>
  <span role="timer" aria-live="off">{{ utcTime }}</span>
</template>
