<script setup lang="ts">
import { onMounted, watch } from "vue";
import { startSocket } from "@/live/socket.ts";
import AppShell from "@/shell/AppShell.vue";
import BootScreen from "@/shell/BootScreen.vue";
import { useBootstrap } from "@/shell/bootstrap.ts";
import SessionProvider from "@/shell/SessionProvider.vue";
import PaletteRoot from "@/features/palette/PaletteRoot.vue";
import { ConfigStatus, StagedBar } from "@/features/changes/index.ts";

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
      <!-- fe-setup: CONFIG rN · n STAGED (renders nothing until the mission has change sets). -->
      <template #topbar-setup-status><ConfigStatus /></template>
      <!-- fe-setup: staged bar under Setup screens (hidden while nothing is staged). -->
      <template #setup-footer><StagedBar /></template>
    </AppShell>
    <PaletteRoot />
  </SessionProvider>
</template>
