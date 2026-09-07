<script setup lang="ts">
import { inject, onBeforeUnmount, onUpdated, useSlots, watchEffect } from "vue";
import CadencePageChrome from "./CadencePageChrome.vue";
import { pageChromeKey, pageRegions, type PageBreadcrumb } from "./page-chrome";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ id?: string; breadcrumbs?: readonly PageBreadcrumb[] }>();
const slots = useSlots();
const chrome = inject(pageChromeKey, null);
const owner = Symbol("page-heading");
const publish = () =>
  chrome?.publish(owner, {
    id: props.id,
    breadcrumbs: props.breadcrumbs,
    regions: pageRegions.filter((region) => Boolean(slots[region])),
  });
watchEffect(publish);
onUpdated(publish);
onBeforeUnmount(() => chrome?.release(owner));
</script>
<template>
  <template v-if="chrome">
    <template v-for="region in pageRegions" :key="region">
      <Teleport v-if="$slots[region] && chrome.targets[region]" :to="chrome.targets[region]!">
        <slot :name="region" />
      </Teleport>
    </template>
  </template>
  <CadencePageChrome v-else :id="id" :breadcrumbs="breadcrumbs">
    <template v-for="(_, region) in $slots" #[region]><slot :name="region" /></template>
  </CadencePageChrome>
</template>
