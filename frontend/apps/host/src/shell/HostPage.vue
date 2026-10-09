<script setup lang="ts">
import { computed, onBeforeUnmount, provide, shallowReactive, shallowRef } from "vue";
import CadencePageChrome from "@cadence/ui/CadencePageChrome.vue";
import {
  pageChromeKey,
  type PageBreadcrumb,
  type PageChrome,
  type PageHeadingContent,
  type PageRegion,
} from "@cadence/ui/page-chrome";
const props = withDefaults(
  defineProps<{
    title: string;
    breadcrumbs?: PageBreadcrumb[];
    workspace?: boolean;
    /** Full-bleed surfaces (e.g. a dashboard) own their identity bar; the host omits its heading. */
    heading?: boolean;
  }>(),
  { heading: true },
);
const content = shallowRef<PageHeadingContent>();
const targets = shallowReactive<PageChrome["targets"]>({});
let owner: symbol | undefined;
let disposed = false;
let publishedSignature = "";
const chrome: PageChrome = {
  targets,
  publish(nextOwner, nextContent) {
    if (disposed) return;
    const signature = JSON.stringify(nextContent);
    if (owner === nextOwner && signature === publishedSignature) return;
    publishedSignature = signature;
    owner = nextOwner;
    content.value = nextContent;
  },
  release(previousOwner) {
    if (owner !== previousOwner || disposed) return;
    owner = undefined;
    publishedSignature = "";
    content.value = undefined;
  },
};
provide(pageChromeKey, chrome);
onBeforeUnmount(() => {
  disposed = true;
});
const breadcrumbs = computed(() => {
  const supplied = content.value?.breadcrumbs;
  const fallback = props.breadcrumbs ?? [];
  if (!supplied?.length) return fallback;
  // The organization/account root is host-owned; resource hierarchy comes from the domain.
  const root = fallback[0];
  if (
    !root ||
    supplied.some((item) => item.label === root.label || (root.href && item.href === root.href))
  )
    return supplied;
  return [root, ...supplied];
});
const has = (region: PageRegion) => content.value?.regions.includes(region);
</script>
<template>
  <div class="cd-page" :class="{ 'cd-page--workspace': workspace }">
    <div
      v-if="heading"
      id="host-page-heading"
      :data-page-heading-source="content ? 'application' : 'route'"
    >
      <CadencePageChrome :id="content?.id" :breadcrumbs="breadcrumbs">
        <template #eyebrow
          ><span :ref="(el) => (targets.eyebrow = el as HTMLElement)" v-show="has('eyebrow')"
        /></template>
        <template #title
          ><span v-if="!has('title')">{{ title }}</span
          ><span :ref="(el) => (targets.title = el as HTMLElement)" v-show="has('title')"
        /></template>
        <template #description
          ><div
            :ref="(el) => (targets.description = el as HTMLElement)"
            v-show="has('description')"
        /></template>
        <template #metadata
          ><span :ref="(el) => (targets.metadata = el as HTMLElement)" v-show="has('metadata')"
        /></template>
        <template #actions
          ><div
            :ref="(el) => (targets.actions = el as HTMLElement)"
            v-show="has('actions')"
            class="cd-page-actions"
        /></template>
      </CadencePageChrome>
    </div>
    <div id="host-page-content" class="cd-page-body"><slot /></div>
  </div>
</template>
