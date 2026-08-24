<script setup lang="ts">
import {reactive, watch} from "vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type Page = {
  title: string
  breadcrumbs: Breadcrumb[]
  submit_label: string
  cancel_label: string
  cancel_href: string
}

type OrganizationForm = {
  display_name: string
  slug: string
}

type OrganizationPayload = {
  organization: OrganizationForm
}

const props = defineProps<{
  page: Page
  form: OrganizationForm
}>()

const emit = defineEmits<{
  validate: [payload: OrganizationPayload]
  save: [payload: OrganizationPayload]
}>()

const organization = reactive<OrganizationForm>({...props.form})
const pendingValidations: OrganizationForm[] = []

const values = (): OrganizationForm => ({
  display_name: organization.display_name,
  slug: organization.slug
})

const sameValues = (left: OrganizationForm, right: OrganizationForm) =>
  left.display_name === right.display_name && left.slug === right.slug

watch(
  () => props.form,
  (serverValues) => {
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )
    const hasNewerTyping =
      acknowledgedIndex >= 0 && acknowledgedIndex < pendingValidations.length - 1

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)

    if (!hasNewerTyping) Object.assign(organization, serverValues)
  },
  {deep: true}
)

const validate = () => {
  const formValues = values()
  pendingValidations.push(formValues)
  emit("validate", {organization: formValues})
}

const save = () => emit("save", {organization: values()})
</script>

<template>
  <div id="admin-organization-new-page" class="space-y-6 max-w-xl">
    <header class="border-b border-primary/20 pb-4">
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
              class="transition-colors hover:text-primary"
            >{{ breadcrumb.label }}</a>
          </template>
        </nav>
        <h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">
          {{ page.title }}
        </h1>
      </div>
    </header>

    <form id="org-form" class="space-y-4" @submit.prevent="save">
      <div class="fieldset mb-3">
        <label for="organization_display_name" class="hud-label mb-1.5 block">
          Display Name
        </label>
        <input
          id="organization_display_name"
          v-model="organization.display_name"
          name="organization[display_name]"
          type="text"
          required
          class="w-full input"
          @input="validate"
        >
      </div>

      <div class="fieldset mb-3">
        <label for="organization_slug" class="hud-label mb-1.5 block">Slug</label>
        <input
          id="organization_slug"
          v-model="organization.slug"
          name="organization[slug]"
          type="text"
          required
          class="w-full input"
          @input="validate"
        >
      </div>

      <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button type="submit" class="btn btn-primary">{{ page.submit_label }}</button>
        <a
          :href="page.cancel_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-ghost"
        >{{ page.cancel_label }}</a>
      </div>
    </form>
  </div>
</template>
