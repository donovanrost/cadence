<script setup lang="ts">
import { computed, onBeforeUnmount, provide, shallowReactive, shallowRef } from "vue";
import CadencePageChrome from "@cadence/ui/CadencePageChrome.vue";
import HostPageHeader from "./HostPageHeader.vue";
import { providePageHeaderHost } from "./page-header-host";
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
    /** The catalog route being shown; its header policy decides what the page may say. */
    route?: string;
    /** The sidebar section, shown when the route opts into an eyebrow. */
    section?: string | null;
  }>(),
  { heading: true, route: "", section: null },
);
const typed = providePageHeaderHost(() => props.route);
const policy = typed.policy;
const eyebrow = computed(() => (policy.value?.eyebrow ? props.section : null));
// The trail ends at the page; a resource page's crumb is the resource's own name.
const routeBreadcrumbs = computed(() => {
  const items = policy.value?.breadcrumbs === false ? [] : (props.breadcrumbs ?? []);
  const title = typed.header.value?.title;
  return title && items.length ? [...items.slice(0, -1), { label: title }] : items;
});
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
      v-if="heading && !content"
      id="host-page-heading"
      :data-page-heading-source="typed.claimed.value ? 'page' : 'route'"
    >
      <HostPageHeader
        :title="title"
        :eyebrow="eyebrow"
        :breadcrumbs="routeBreadcrumbs"
        :description="policy?.description ?? null"
        :header="typed.header.value"
      />
    </div>
    <!-- Pages not yet on useOpsHeader or useManagementHeader publish header markup through CadencePageHeading. -->
    <div v-else-if="heading" id="host-page-heading" data-page-heading-source="application">
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
