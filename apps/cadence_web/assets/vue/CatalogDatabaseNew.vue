<script setup lang="ts">
type Breadcrumb = {
  label: string
  href: string | null
}

type Page = {
  id: string
  heading: string
  breadcrumbs: Breadcrumb[]
  cancel: {
    id: string
    label: string
    href: string
  }
}

defineProps<{
  page: Page
}>()
</script>

<template>
  <div :id="page.id" class="space-y-6 max-w-2xl">
    <header class="border-b border-primary/20 pb-4">
      <div>
        <div>
          <nav
            aria-label="Breadcrumb"
            class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
          >
            <template
              v-for="(breadcrumb, index) in page.breadcrumbs"
              :key="`${index}-${breadcrumb.label}`"
            >
              <span v-if="index > 0" class="text-base-content/20" aria-hidden="true">/</span>
              <span v-if="breadcrumb.href === null" class="text-primary/90">
                {{ breadcrumb.label }}
              </span>
              <a
                v-else
                :href="breadcrumb.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="hover:text-primary transition-colors"
              >{{ breadcrumb.label }}</a>
            </template>
          </nav>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ page.heading }}
          </h1>
        </div>
      </div>
    </header>

    <slot name="upload_form" />

    <div>
      <a
        :id="page.cancel.id"
        :href="page.cancel.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-ghost"
      >{{ page.cancel.label }}</a>
    </div>
  </div>
</template>
