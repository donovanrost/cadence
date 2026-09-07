<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";

type DefinitionItem = {
  label: string;
  value: number | string;
};

type DashboardSnapshot = {
  id: string;
  eyebrow: string;
  name: string;
  policy: {
    id: string;
    text: string;
  };
  warning: string;
  definition: {
    id: string;
    items: DefinitionItem[];
  };
  action: {
    id: string;
    label: string;
    href: string;
  };
};

defineProps<{ snapshot: DashboardSnapshot }>();
</script>

<template>
  <CadenceOpsViewport :id="snapshot.id" class="">
    <div class="space-y-5">
      <CadencePageHeading>
        <template #title>{{ snapshot.name }}</template>
        <template #eyebrow>{{ snapshot.eyebrow }}</template>
        <template #description>{{ snapshot.policy.text }} {{ snapshot.warning }}</template>
      </CadencePageHeading>
      <section :id="snapshot.definition.id" class="grid gap-3 sm:grid-cols-3">
        <div
          v-for="item in snapshot.definition.items"
          :key="item.label"
          class="border border-base-300 p-4"
        >
          <p class="hud-label">{{ item.label }}</p>
          <p class="mt-2 text-xl font-semibold">{{ item.value }}</p>
        </div>
      </section>
      <a
        :id="snapshot.action.id"
        :href="snapshot.action.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-outline"
      >
        {{ snapshot.action.label }}
      </a>
    </div>
  </CadenceOpsViewport>
</template>
