<script setup lang="ts">
import { Fragment, defineComponent, h, isVNode, type VNodeChild } from "vue";
import type { BreadcrumbsPresentation } from "@cadence/ui";

const props = defineProps<{ breadcrumbs?: BreadcrumbsPresentation }>();

const slotNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60";

const flattenFragments = (children: VNodeChild[]): VNodeChild[] =>
  children.flatMap((child) => {
    if (Array.isArray(child)) return flattenFragments(child);

    if (isVNode(child) && child.type === Fragment && Array.isArray(child.children)) {
      return flattenFragments(child.children);
    }

    return [child];
  });

const TransparentBreadcrumbNav = defineComponent({
  name: "TransparentBreadcrumbNav",
  inheritAttrs: false,
  setup(_, { slots }) {
    return () =>
      h(
        "nav",
        { "aria-label": "Breadcrumb", class: slotNavClass },
        flattenFragments(slots.default?.() ?? []),
      );
  },
});
</script>

<template>
  <template v-if="props.breadcrumbs">
    <nav v-bind="props.breadcrumbs.attrs">
      <template v-for="item in props.breadcrumbs.items" :key="item.key">
        <span v-if="item.separator" v-bind="item.separator.attrs">
          {{ item.separator.text }}
        </span>
        <a v-if="item.link" v-bind="item.link.attrs">{{ item.link.text }}</a>
        <span v-if="item.current" v-bind="item.current.attrs">
          {{ item.current.text }}
        </span>
      </template>
    </nav>
  </template>
  <TransparentBreadcrumbNav v-else>
    <slot />
  </TransparentBreadcrumbNav>
</template>
