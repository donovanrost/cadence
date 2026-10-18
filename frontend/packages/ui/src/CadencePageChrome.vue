<script setup lang="ts">
import CadencePageTitle from "./CadencePageTitle.vue";
import CadenceBreadcrumbTrail from "./CadenceBreadcrumbTrail.vue";
import CadencePageDescription from "./CadencePageDescription.vue";
import CadencePageActions from "./CadencePageActions.vue";
import type { PageBreadcrumb } from "./page-chrome";
defineProps<{ breadcrumbs?: readonly PageBreadcrumb[] }>();
</script>
<template>
  <header class="cd-page-header">
    <CadenceBreadcrumbTrail :items="breadcrumbs ?? []" />
    <div class="cd-page-header__row">
      <div class="cd-page-header__content">
        <div class="cd-page-eyebrow"><slot name="eyebrow" /></div>
        <div class="cd-page-header__identity">
          <CadencePageTitle><slot name="title" /></CadencePageTitle>
          <div class="cd-page-metadata"><slot name="metadata" /></div>
        </div>
        <CadencePageDescription><slot name="description" /></CadencePageDescription>
      </div>
      <CadencePageActions><slot name="actions" /></CadencePageActions>
    </div>
  </header>
</template>
