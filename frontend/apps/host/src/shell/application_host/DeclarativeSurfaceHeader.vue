<script setup lang="ts">
import { headerText, useManagementHeaders } from "@cadence/plugin-sdk/page-header";

/** Describes a declarative application surface's header to the host page around it. */
const props = defineProps<{ title: string; subtitle: string | null }>();
const header = () => ({
  title: headerText(props.title, 120) ?? "Application",
  description: headerText(props.subtitle),
});
useManagementHeaders({
  "/missions/:mission_id/applications/:application_key/:surface_id": header,
  "/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/:surface_id":
    header,
});
</script>
<template><slot /></template>
