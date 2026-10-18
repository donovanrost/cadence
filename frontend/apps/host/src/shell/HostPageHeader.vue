<script setup lang="ts">
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
import CadencePageChrome from "@cadence/ui/CadencePageChrome.vue";
import type { PageBreadcrumb } from "@cadence/ui/page-chrome";
import type { AdmittedHeader } from "@cadence/plugin-sdk/page-header-validation";
import HostHeaderActions from "./HostHeaderActions.vue";

/** The one page header: route title and policy, host context, and the page's admitted data. */
defineProps<{
  title: string;
  eyebrow: string | null;
  breadcrumbs: readonly PageBreadcrumb[];
  description: string | null;
  header: AdmittedHeader | null;
}>();
</script>

<template>
  <CadencePageChrome :breadcrumbs="breadcrumbs">
    <template v-if="eyebrow" #eyebrow>{{ eyebrow }}</template>
    <template #title>{{ header?.title ?? title }}</template>
    <template v-if="header?.status || header?.identifier || header?.facts?.length" #metadata>
      <span class="flex flex-wrap items-center gap-2">
        <CadenceBadge v-if="header.status" :tone="header.status.tone">{{
          header.status.label
        }}</CadenceBadge>
        <span
          v-if="header.identifier"
          id="host-page-identifier"
          class="break-all font-mono text-xs text-base-content/60"
          >{{ header.identifier }}</span
        >
        <span
          v-for="fact in header.facts ?? []"
          :key="fact"
          class="font-mono text-xs text-base-content/60"
          >{{ fact }}</span
        >
      </span>
    </template>
    <template v-if="header?.description ?? description" #description>{{
      header?.description ?? description
    }}</template>
    <template v-if="header" #actions><HostHeaderActions :header="header" /></template>
  </CadencePageChrome>
</template>
