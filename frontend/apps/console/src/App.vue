<script setup lang="ts">
import { onMounted, watch } from "vue";
import { startSocket } from "@/live/socket.ts";
import AppShell from "@/shell/AppShell.vue";
import BootScreen from "@/shell/BootScreen.vue";
import { useBootstrap } from "@/shell/bootstrap.ts";
import SessionProvider from "@/shell/SessionProvider.vue";

const { state, load } = useBootstrap();
onMounted(() => void load());

watch(state, (current) => {
  if (current.status !== "ready") return;
  startSocket(current.session.socket.path, current.session.csrf_token);
});
</script>

<template>
  <BootScreen v-if="state.status === 'loading'" />
  <BootScreen v-else-if="state.status === 'failed'" :error="state.error" @retry="load" />
  <SessionProvider v-else :session="state.session">
    <AppShell />
    <!-- fe-ops: mount the ⌘K palette here (it reads usePalette() from @/shell). -->
  </SessionProvider>
</template>
