<script setup lang="ts">
import { AlarmConditionsLegacyRedirect } from "@cadence/limits-and-alarming/alarm-conditions";
defineProps<{ mission_id: unknown; query: unknown }>();
</script>
<template><AlarmConditionsLegacyRedirect :mission_id="mission_id" :query="query" /></template>
