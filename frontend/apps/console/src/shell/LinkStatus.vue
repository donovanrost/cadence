<script setup lang="ts">
import { useConnection } from "@/live/socket.ts";
import { ApTag } from "@/ui";

/** Visible only when the live socket is down: live values on screen are no longer fresh. */
const connection = useConnection();
</script>

<template>
  <div
    v-if="connection === 'offline'"
    role="status"
    class="flex items-center border-r border-hairline px-[18px]"
  >
    <ApTag state="stale" label="Live link lost · data stale" />
  </div>
</template>
