<script setup lang="ts">
import { onMounted, onUnmounted } from "vue";
import type { Session } from "@/api/session.ts";
import { seedAdminMode } from "./admin-mode.ts";
import { provideSession } from "./session.ts";

const props = defineProps<{ session: Readonly<Session> }>();
provideSession(props.session);
seedAdminMode(props.session);

// e2e hook: the shell is interactive once the session is provided and children mounted.
onMounted(() => document.body.setAttribute("data-shell-ready", ""));
onUnmounted(() => document.body.removeAttribute("data-shell-ready"));
</script>

<template>
  <slot />
</template>
