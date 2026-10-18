<script setup lang="ts">
import { inject } from "vue";
import { contactNavigationKey } from "./contact-navigation";
defineProps<{ href: string }>();
const navigation = inject(contactNavigationKey, undefined);
</script>
<template>
  <component :is="navigation?.link ?? 'a'" :href="href"><slot /></component>
</template>
