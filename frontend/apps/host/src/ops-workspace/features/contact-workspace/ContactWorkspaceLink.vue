<script setup lang="ts">
import { computed, inject } from "vue";
import { RouterLink } from "vue-router";
import { workspaceDestination } from "./contracts";
import { workspaceBootstrapKey } from "./router";
const props = defineProps<{ href: string }>();
const bootstrap = inject(workspaceBootstrapKey);
if (!bootstrap) throw Error("Missing contact workspace");
const mission = bootstrap.missionId;
const to = computed(() => workspaceDestination(props.href, mission, window.location.origin));
</script>
<template>
  <RouterLink v-if="to" :to="to"><slot /></RouterLink>
  <a v-else :href="href"><slot /></a>
</template>
