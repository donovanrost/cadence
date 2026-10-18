<script setup lang="ts">
import { computed, inject, onBeforeUnmount, onUpdated, useSlots, watchEffect } from "vue";
import CadencePageChrome from "./CadencePageChrome.vue";
import { pageChromeKey, pageRegions, type PageBreadcrumb } from "./page-chrome";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ id?: string; breadcrumbs?: readonly PageBreadcrumb[] }>();
const slots = useSlots();
const chrome = inject(pageChromeKey, null);
const owner = Symbol("page-heading");
const headingAttrs = computed(() => ({
  ...(props.id === undefined ? {} : { id: props.id }),
  ...(props.breadcrumbs === undefined ? {} : { breadcrumbs: props.breadcrumbs }),
}));
const publish = () =>
  chrome?.publish(owner, {
    ...headingAttrs.value,
    regions: pageRegions.filter((region) => Boolean(slots[region])),
  });
watchEffect(publish);
onUpdated(publish);
onBeforeUnmount(() => chrome?.release(owner));
</script>
<template>
  <template v-if="chrome">
    <template v-for="(target, region) in chrome.targets" :key="region">
      <Teleport v-if="$slots[region] && target" :to="target">
        <slot :name="region" />
      </Teleport>
    </template>
  </template>
  <CadencePageChrome v-else v-bind="headingAttrs">
    <template v-for="(_, region) in $slots" #[region]><slot :name="region" /></template>
  </CadencePageChrome>
</template>
