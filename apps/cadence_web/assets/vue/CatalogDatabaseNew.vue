<script setup lang="ts">
import CatalogUploadForm from "./CatalogUploadForm.vue"
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"

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

type CatalogUploadFormProps = InstanceType<typeof CatalogUploadForm>["$props"]

defineProps<{
  page: Page
  form: CatalogUploadFormProps["form"]
  upload: CatalogUploadFormProps["upload"]
  detected_importer: CatalogUploadFormProps["detected_importer"]
  submit_disabled: boolean
}>()

const emit = defineEmits<{
  validate: [payload: Record<string, Record<string, string>>]
  "cancel-upload": [payload: {ref: string}]
}>()
</script>

<template>
  <div :id="page.id" class="space-y-6 max-w-2xl">
    <CadencePageHeaderFrame variant="compact">
      <div>
        <div>
          <CadenceBreadcrumbs>
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
          </CadenceBreadcrumbs>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ page.heading }}
          </h1>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <CatalogUploadForm
      :form="form"
      :upload="upload"
      :detected_importer="detected_importer"
      :submit_disabled="submit_disabled"
      @validate="emit('validate', $event)"
      @cancel-upload="emit('cancel-upload', $event)"
    />

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
