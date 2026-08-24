<script setup lang="ts">
import {reactive, watch} from "vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type RoleOption = {
  label: string
  value: string
}

type Page = {
  title: string
  subtitle: string
  breadcrumbs: Breadcrumb[]
  role_options: RoleOption[]
  submit_label: string
  cancel_label: string
  cancel_href: string
}

type InviteForm = {
  email: string
  display_name: string
  membership_role: string
  grant_platform_admin: boolean
}

type SerializedInviteForm = {
  email: string
  display_name: string
  membership_role: string
  grant_platform_admin: "true" | "false"
}

type InvitePayload = {
  invite: SerializedInviteForm
}

const props = defineProps<{
  page: Page
  form: InviteForm
}>()

const emit = defineEmits<{
  validate: [payload: InvitePayload]
  save: [payload: InvitePayload]
}>()

const invite = reactive<InviteForm>({...props.form})
const pendingValidations: InviteForm[] = []

const values = (): InviteForm => ({
  email: invite.email,
  display_name: invite.display_name,
  membership_role: invite.membership_role,
  grant_platform_admin: invite.grant_platform_admin
})

const serializedValues = (formValues: InviteForm): SerializedInviteForm => ({
  email: formValues.email,
  display_name: formValues.display_name,
  membership_role: formValues.membership_role,
  grant_platform_admin: formValues.grant_platform_admin ? "true" : "false"
})

const sameValues = (left: InviteForm, right: InviteForm) =>
  left.email === right.email &&
  left.display_name === right.display_name &&
  left.membership_role === right.membership_role &&
  left.grant_platform_admin === right.grant_platform_admin

watch(
  () => props.form,
  (serverValues) => {
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )
    const latestPending = pendingValidations[pendingValidations.length - 1]
    const hasNewerTyping =
      acknowledgedIndex >= 0
        ? acknowledgedIndex < pendingValidations.length - 1
        : latestPending !== undefined && !sameValues(latestPending, serverValues)

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)

    if (!hasNewerTyping) Object.assign(invite, serverValues)
  },
  {deep: true}
)

const validate = () => {
  const formValues = values()
  pendingValidations.push(formValues)
  emit("validate", {invite: serializedValues(formValues)})
}

const save = () => {
  const formValues = values()
  emit("save", {invite: serializedValues(formValues)})
}
</script>

<template>
  <div id="admin-organization-invite-page" class="space-y-6 max-w-xl">
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
        <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
          {{ page.title }}
        </h1>
        <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
      </div>
    </header>

    <form id="invite-form" class="space-y-4" @submit.prevent="save">
      <div class="fieldset mb-3">
        <label for="invite_email" class="hud-label block mb-1.5">Email</label>
        <input
          id="invite_email"
          v-model="invite.email"
          name="invite[email]"
          type="email"
          placeholder="operator@example.com"
          required
          class="w-full input"
          @input="validate"
        >
      </div>

      <div class="fieldset mb-3">
        <label for="invite_display_name" class="hud-label block mb-1.5">Display Name</label>
        <input
          id="invite_display_name"
          v-model="invite.display_name"
          name="invite[display_name]"
          type="text"
          placeholder="Flight Operator"
          class="w-full input"
          @input="validate"
        >
      </div>

      <div class="fieldset mb-3">
        <label for="invite_membership_role" class="hud-label block mb-1.5">Role</label>
        <select
          id="invite_membership_role"
          v-model="invite.membership_role"
          name="invite[membership_role]"
          class="w-full select"
          @change="validate"
        >
          <option v-for="option in page.role_options" :key="option.value" :value="option.value">
            {{ option.label }}
          </option>
        </select>
      </div>

      <div class="fieldset mb-3">
        <label class="flex cursor-pointer items-start gap-3" for="invite_grant_platform_admin">
          <input name="invite[grant_platform_admin]" type="hidden" value="false">
          <input
            id="invite_grant_platform_admin"
            v-model="invite.grant_platform_admin"
            name="invite[grant_platform_admin]"
            type="checkbox"
            value="true"
            aria-describedby="invite_grant_platform_admin-description"
            class="checkbox checkbox-sm mt-0.5"
            @change="validate"
          >
          <span>
            <span class="block text-sm font-medium">Grant platform admin</span>
            <span
              id="invite_grant_platform_admin-description"
              class="mt-0.5 block text-xs text-base-content/70"
            >Platform admins can manage all organizations and system settings.</span>
          </span>
        </label>
      </div>

      <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button id="invite-submit" type="submit" class="btn btn-primary">
          {{ page.submit_label }}
        </button>
        <a
          id="invite-cancel"
          :href="page.cancel_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-ghost"
        >{{ page.cancel_label }}</a>
      </div>
    </form>
  </div>
</template>
