<script setup lang="ts">
import {onMounted, reactive, ref, watch} from "vue"
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"

type Organization = {
  organization_id: string
  display_name: string
  slug: string
}

type Navigation = {
  platform_admin_href: string
  organizations_href: string
  invite_href: string
  open_organization_action: string
}

type Member = {
  id: string
  display_name: string
  email: string
  role: string
  role_label: string
}

type Invitation = {
  id: string
  invitation_id: string
  email: string
  role: string
  role_label: string
  grant_platform_admin: boolean
  expires_on: string
}

type ServiceIdentity = {
  id: string
  service_identity_id: string
  display_name: string
  token_hint: string | null
  lifecycle_state: string
  lifecycle_state_label: string
}

type ServiceIdentityForm = {
  display_name: string
  service_identity_id: string
}

type IssuedServiceToken = {
  service_identity_id: string
  display_name: string
  api_token: string
}

const props = defineProps<{
  organization: Organization
  navigation: Navigation
  members: Member[]
  invitations: Invitation[]
  service_identities: ServiceIdentity[]
  service_identity_form: ServiceIdentityForm
  issued_service_token: IssuedServiceToken | null
}>()

const emit = defineEmits<{
  "issue-service-identity": [payload: {service_identity: ServiceIdentityForm}]
  "dismiss-service-token": []
}>()

const csrfToken = ref("")
const serviceIdentityForm = reactive<ServiceIdentityForm>({...props.service_identity_form})

watch(
  () => props.service_identity_form,
  (values) => Object.assign(serviceIdentityForm, values),
  {deep: true}
)

onMounted(() => {
  csrfToken.value =
    document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
})

const issueServiceIdentity = () => {
  emit("issue-service-identity", {
    service_identity: {
      display_name: serviceIdentityForm.display_name,
      service_identity_id: serviceIdentityForm.service_identity_id
    }
  })
}
</script>

<template>
  <main id="admin-organization-detail" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <CadenceBreadcrumbs>
        <a
          :href="navigation.platform_admin_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="transition-colors hover:text-primary"
        >Platform Admin</a>
        <span class="text-base-content/20" aria-hidden="true">/</span>
        <a
          :href="navigation.organizations_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="transition-colors hover:text-primary"
        >Organizations</a>
        <span class="text-base-content/20" aria-hidden="true">/</span>
        <span class="text-primary/90">{{ organization.display_name }}</span>
      </CadenceBreadcrumbs>

      <div class="mt-2 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 class="text-2xl font-bold tracking-tight text-base-content">
            {{ organization.display_name }}
          </h1>
          <p class="mt-1 font-mono text-sm text-base-content/70">{{ organization.slug }}</p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <form
            id="open-organization-form"
            :action="navigation.open_organization_action"
            method="post"
          >
            <input type="hidden" name="_csrf_token" :value="csrfToken">
            <input type="hidden" name="_method" value="put">
            <input
              type="hidden"
              name="organization_id"
              :value="organization.organization_id"
            >
            <button type="submit" class="btn btn-secondary btn-sm">Open organization</button>
          </form>
          <a
            id="admin-organization-invite-link"
            :href="navigation.invite_href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-primary btn-sm"
          >Invite User</a>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="grid gap-6 xl:grid-cols-2">
      <section id="admin-organization-members" aria-labelledby="admin-organization-members-title">
        <h2 id="admin-organization-members-title" class="mb-3 text-lg font-bold">Members</h2>

        <div
          v-if="members.length === 0"
          id="organization-members-empty"
          class="border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        >
          <p class="hud-label">No members yet.</p>
          <p class="mx-auto mt-2 max-w-md text-sm text-base-content/70">
            Invite someone to get started.
          </p>
        </div>

        <div v-else class="overflow-x-auto border border-base-300 bg-base-200">
          <CadenceTableFrame id="org-members-table">
            <thead>
              <tr>
                <th class="hud-label">User</th>
                <th class="hud-label">Role</th>
              </tr>
            </thead>
            <tbody id="org-members-table-body">
              <tr v-for="member in members" :id="member.id" :key="member.id">
                <td>
                  <p class="font-semibold">{{ member.display_name }}</p>
                  <p class="text-sm text-base-content/70">{{ member.email }}</p>
                </td>
                <td>
                  <span
                    :data-membership-role="member.role"
                    class="bg-base-300 px-2 py-1 font-mono text-[0.65rem] uppercase tracking-wide"
                  >{{ member.role_label }}</span>
                </td>
              </tr>
            </tbody>
          </CadenceTableFrame>
        </div>
      </section>

      <section
        id="admin-organization-invitations"
        aria-labelledby="admin-organization-invitations-title"
      >
        <h2 id="admin-organization-invitations-title" class="mb-3 text-lg font-bold">
          Pending Invitations
        </h2>

        <p
          v-if="invitations.length === 0"
          id="organization-invitations-empty"
          class="text-sm text-base-content/60"
        >No pending invitations.</p>

        <div v-else class="space-y-2">
          <article
            v-for="invitation in invitations"
            :id="invitation.id"
            :key="invitation.invitation_id"
            class="border border-base-300 bg-base-200 p-3"
          >
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div class="min-w-0">
                <p class="truncate font-semibold">{{ invitation.email }}</p>
                <p class="mt-1 text-sm text-base-content/60">
                  Role: {{ invitation.role_label }}
                  <template v-if="invitation.grant_platform_admin"> · Platform Admin</template>
                </p>
              </div>
              <p class="shrink-0 text-xs text-base-content/60">
                Expires {{ invitation.expires_on }}
              </p>
            </div>
          </article>
        </div>
      </section>
    </div>

    <section id="admin-service-identities" class="space-y-3" aria-labelledby="service-identities-title">
      <div>
        <h2 id="service-identities-title" class="text-lg font-semibold">Service identities</h2>
        <p class="mt-1 max-w-2xl text-sm text-base-content/70">
          Issue organization-scoped credentials for product API clients.
        </p>
      </div>

      <div
        v-if="issued_service_token"
        id="issued-service-token"
        class="border border-primary/30 bg-primary/5 p-4"
      >
        <div class="space-y-3">
          <div>
            <p class="font-semibold">Copy this API token now</p>
            <p class="text-sm text-base-content/60">Cadence will not display it again.</p>
          </div>
          <code class="block break-all border border-primary/20 bg-base-300 p-3 text-xs">
            {{ issued_service_token.api_token }}
          </code>
          <button
            id="dismiss-issued-service-token"
            type="button"
            class="btn btn-secondary btn-sm"
            @click="emit('dismiss-service-token')"
          >Done</button>
        </div>
      </div>

      <div class="overflow-x-auto border border-base-300 bg-base-200">
        <CadenceTableFrame id="service-identities-table">
          <thead>
            <tr>
              <th class="hud-label">Name</th>
              <th class="hud-label">ID</th>
              <th class="hud-label">Token hint</th>
              <th class="hud-label">State</th>
            </tr>
          </thead>
          <tbody id="service-identities-table-body">
            <tr
              v-for="identity in service_identities"
              :id="identity.id"
              :key="identity.service_identity_id"
              class="border-l-2 border-l-transparent transition-colors hover:border-l-primary/60"
            >
              <td>{{ identity.display_name }}</td>
              <td class="font-mono text-sm">{{ identity.service_identity_id }}</td>
              <td class="font-mono text-sm">{{ identity.token_hint }}</td>
              <td>
                <span
                  :data-service-identity-state="identity.lifecycle_state"
                  class="font-mono text-[0.65rem] uppercase tracking-wide text-success"
                >{{ identity.lifecycle_state_label }}</span>
              </td>
            </tr>
          </tbody>
        </CadenceTableFrame>
      </div>

      <form
        id="service-identity-form"
        class="grid gap-3 md:grid-cols-[1fr_1fr_auto] md:items-end"
        @submit.prevent="issueServiceIdentity"
      >
        <div class="fieldset mb-3">
          <label>
            <span class="hud-label mb-1.5 block">Display name</span>
            <input
              id="service_identity_display_name"
              v-model="serviceIdentityForm.display_name"
              name="service_identity[display_name]"
              type="text"
              class="input w-full"
              required
            >
          </label>
        </div>
        <div class="fieldset mb-3">
          <label>
            <span class="hud-label mb-1.5 block">ID (optional)</span>
            <input
              id="service_identity_service_identity_id"
              v-model="serviceIdentityForm.service_identity_id"
              name="service_identity[service_identity_id]"
              type="text"
              class="input w-full"
              placeholder="Generated when blank"
            >
          </label>
        </div>
        <button type="submit" class="btn btn-primary btn-sm mb-3">Issue credential</button>
      </form>
    </section>
  </main>
</template>
