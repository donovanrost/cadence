<script setup lang="ts">
import CadenceOpsViewport from "./ui/components/CadenceOpsViewport.vue"

type DefinitionItem = {
  label: string
  value: number | string
}

type DashboardSnapshot = {
  id: string
  eyebrow: string
  name: string
  policy: {
    id: string
    text: string
  }
  warning: string
  definition: {
    id: string
    items: DefinitionItem[]
  }
  action: {
    id: string
    label: string
    href: string
  }
}

defineProps<{snapshot: DashboardSnapshot}>()
</script>

<template>
  <CadenceOpsViewport :id="snapshot.id" class="p-6">
    <div class="mx-auto max-w-4xl space-y-5">
      <header class="border border-primary/30 bg-base-200/30 p-6">
        <p class="hud-label">{{ snapshot.eyebrow }}</p>
        <h1 class="mt-2 text-2xl font-semibold">{{ snapshot.name }}</h1>
        <p :id="snapshot.policy.id" class="mt-2 text-sm text-base-content/60">
          {{ snapshot.policy.text }}
        </p>
        <p class="mt-3 text-xs text-warning">
          {{ snapshot.warning }}
        </p>
      </header>
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
