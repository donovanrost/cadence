<script setup lang="ts">
import { onMounted, watch } from "vue";
import { startSocket } from "@/live/socket.ts";
import AppShell from "@/shell/AppShell.vue";
import BootScreen from "@/shell/BootScreen.vue";
import { useBootstrap } from "@/shell/bootstrap.ts";
import SessionProvider from "@/shell/SessionProvider.vue";
import PaletteRoot from "@/features/palette/PaletteRoot.vue";

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
    <AppShell>
      <!-- fe-ops: <FleetStatusTag /> from @/features/fleet goes here (Ops top bar). -->
      <template #topbar-status />
      <!-- fe-setup: <ConfigStatus /> (CONFIG rN · n STAGED) for the Setup top bar. -->
      <template #topbar-setup-status />
      <!-- fe-setup: <StagedBar /> under Setup screens. -->
      <template #setup-footer />
    </AppShell>
    <PaletteRoot />
  </SessionProvider>
</template>
