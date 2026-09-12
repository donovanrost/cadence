<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import { organizationHref } from "../../shared/platform-contract";
import {
  detailHref,
  readIssueResult,
  type OrganizationDetail,
  type Act,
  type Token,
} from "./contracts";
const props = defineProps<{
  model: OrganizationDetail;
  csrfToken: string;
  act: Act;
  refresh: () => Promise<void>;
}>();
const form = reactive({ display_name: "", service_identity_id: "" });
const pending = ref(false),
  uncertain = ref(false),
  completed = ref(false),
  message = ref("");
const errors = ref<Record<string, string>>({});
const issued = ref<Token | null>(null);
const disabled = computed(
  () => pending.value || uncertain.value || completed.value || !!props.model.issued_identity,
);
const role = (value: string) =>
  value === "organization_admin"
    ? "Organization admin"
    : value === "mission_admin"
      ? "Mission admin"
      : "Member";
async function issue() {
  if (disabled.value) return;
  pending.value = true;
  errors.value = {};
  message.value = "";
  try {
    const result = readIssueResult(await props.act("issue_service_identity", { ...form }));
    if (result.status === "issued") {
      issued.value = result.identity;
      completed.value = true;
      form.display_name = "";
      form.service_identity_id = "";
    } else if (result.status === "invalid") errors.value = result.errors;
    else message.value = "Service identity issuance is unavailable. Your values have been kept.";
  } catch {
    uncertain.value = true;
    message.value =
      "The issuance outcome is unknown. Refresh this page to check the identity list before starting another form.";
  } finally {
    pending.value = false;
  }
}
</script>
<template>
  <main id="admin-organization-detail" class="space-y-6">
    <CadencePageHeading
      :breadcrumbs="[
        { label: 'Platform Admin', href: '/admin' },
        { label: 'Organizations', href: '/admin/organizations' },
        { label: model.organization.name, href: null },
      ]"
    >
      <template #title>{{ model.organization.name }}</template
      ><template #description>{{ model.organization.slug }}</template>
      <template #actions>
        <form id="open-organization-form" action="/session/organization" method="post">
          <input type="hidden" name="_csrf_token" :value="csrfToken" /><input
            type="hidden"
            name="_method"
            value="put"
          /><input type="hidden" name="organization_id" :value="model.organization.id" />
          <button type="submit" class="btn btn-secondary btn-sm" :disabled="!csrfToken">
            Open organization
          </button>
        </form>
        <a
          id="admin-organization-invite-link"
          :href="organizationHref(model.organization.id) + '/invite'"
          class="btn btn-primary btn-sm"
          >Invite user</a
        >
      </template>
    </CadencePageHeading>
    <div class="grid gap-6 xl:grid-cols-2">
      <section
        id="admin-organization-members"
        aria-labelledby="admin-organization-members-title"
        class="card border border-base-300 bg-base-200 p-6 space-y-4"
      >
        <h2 id="admin-organization-members-title" class="text-lg font-semibold">Members</h2>
        <p
          v-if="!model.members.entries.length"
          id="organization-members-empty"
          class="text-sm text-base-content/60"
        >
          No members on this page.
        </p>
        <ul v-else id="org-members-list" class="divide-y divide-base-300">
          <li
            v-for="member in model.members.entries"
            :id="`organization-member-${member.id}`"
            :key="member.id"
            class="py-3"
          >
            <p class="font-semibold break-words">{{ member.name }}</p>
            <p class="text-sm text-base-content/70 break-all">{{ member.email }}</p>
            <p class="mt-2 text-xs" :data-membership-role="member.role">
              {{ role(member.role)
              }}<span v-if="member.user_state === 'disabled'"> · Account disabled</span>
            </p>
          </li>
        </ul>
        <nav aria-label="Member pages" class="flex flex-wrap gap-3">
          <a
            v-if="model.query.members_after"
            id="organization-members-first"
            :href="detailHref(model.organization.id, model.query, { members_after: '' })"
            class="btn btn-sm"
            >First members</a
          ><a
            v-if="model.members.next_after"
            id="organization-members-next"
            :href="
              detailHref(model.organization.id, model.query, {
                members_after: model.members.next_after,
              })
            "
            class="btn btn-sm"
            >Next members</a
          >
        </nav>
      </section>
      <section
        id="admin-organization-invitations"
        aria-labelledby="admin-organization-invitations-title"
        class="card border border-base-300 bg-base-200 p-6 space-y-4"
      >
        <h2 id="admin-organization-invitations-title" class="text-lg font-semibold">
          Pending invitations
        </h2>
        <p
          v-if="!model.invitations.entries.length"
          id="organization-invitations-empty"
          class="text-sm text-base-content/60"
        >
          No pending invitations on this page.
        </p>
        <article
          v-for="invitation in model.invitations.entries"
          :id="`organization-invitation-${invitation.id}`"
          :key="invitation.id"
          class="border-b border-base-300 py-3 space-y-2"
        >
          <p class="font-semibold break-all">{{ invitation.email }}</p>
          <p class="text-sm text-base-content/70">
            {{ role(invitation.role)
            }}<span v-if="invitation.grant_platform_admin"> · Platform admin eligibility</span>
          </p>
          <p class="text-xs text-base-content/60">
            Expires
            <time :datetime="invitation.expires_at">{{
              new Date(invitation.expires_at).toISOString().slice(0, 10)
            }}</time>
            UTC
          </p>
        </article>
        <nav aria-label="Invitation pages" class="flex flex-wrap gap-3">
          <a
            v-if="model.query.invitations_after"
            id="organization-invitations-first"
            :href="detailHref(model.organization.id, model.query, { invitations_after: '' })"
            class="btn btn-sm"
            >First invitations</a
          ><a
            v-if="model.invitations.next_after"
            id="organization-invitations-next"
            :href="
              detailHref(model.organization.id, model.query, {
                invitations_after: model.invitations.next_after,
              })
            "
            class="btn btn-sm"
            >Next invitations</a
          >
        </nav>
      </section>
    </div>
    <section
      id="admin-service-identities"
      aria-labelledby="service-identities-title"
      class="card border border-base-300 bg-base-200 p-6 space-y-5"
    >
      <h2 id="service-identities-title" class="text-lg font-semibold">Service identities</h2>
      <section
        v-if="issued"
        id="issued-service-token"
        class="border border-primary/40 bg-primary/5 p-4 space-y-3"
        aria-label="New API token"
      >
        <p class="font-semibold">Copy this API token now</p>
        <p class="text-sm text-base-content/70">Cadence will not display it again.</p>
        <code id="issued-service-token-value" class="block break-all bg-base-300 p-3 text-xs">{{
          issued.api_token
        }}</code>
        <button
          id="dismiss-issued-service-token"
          type="button"
          class="btn btn-sm"
          @click="issued = null"
        >
          Done
        </button>
      </section>
      <p
        v-else-if="model.issued_identity || completed"
        id="service-identity-issued"
        role="status"
        class="text-sm"
      >
        A service identity was created during this visit. Its token is no longer displayed here.
      </p>
      <p
        v-if="!model.services.entries.length"
        id="service-identities-empty"
        class="text-sm text-base-content/60"
      >
        No service identities on this page.
      </p>
      <ul v-else id="service-identities-list" class="divide-y divide-base-300">
        <li
          v-for="identity in model.services.entries"
          :id="`service-identity-${identity.id}`"
          :key="identity.id"
          class="py-3 space-y-1"
        >
          <p class="font-semibold break-words">{{ identity.name }}</p>
          <p class="font-mono text-xs break-all">{{ identity.id }}</p>
          <p class="text-xs text-base-content/70">
            {{ identity.lifecycle_state === "active" ? "Active" : "Disabled" }} ·
            {{ identity.capabilities.map(role).join(", ") || "No administrative capability" }}
          </p>
          <p v-if="identity.mission_id" class="text-xs break-all">
            Mission: {{ identity.mission_id }}
          </p>
          <p v-if="identity.token_hint" class="font-mono text-xs text-base-content/60">
            Token hint: {{ identity.token_hint }}
          </p>
        </li>
      </ul>
      <nav aria-label="Service identity pages" class="flex flex-wrap gap-3">
        <a
          v-if="model.query.services_after"
          id="service-identities-first"
          :href="detailHref(model.organization.id, model.query, { services_after: '' })"
          class="btn btn-sm"
          >First identities</a
        ><a
          v-if="model.services.next_after"
          id="service-identities-next"
          :href="
            detailHref(model.organization.id, model.query, {
              services_after: model.services.next_after,
            })
          "
          class="btn btn-sm"
          >Next identities</a
        >
      </nav>
      <form
        id="service-identity-form"
        class="space-y-4 border-t border-base-300 pt-5"
        @submit.prevent="issue"
      >
        <h3 class="font-semibold">Issue a service identity</h3>
        <p class="text-sm text-base-content/70">
          This credential grants organization-admin access to {{ model.organization.name }}.
        </p>
        <div class="grid gap-3 md:grid-cols-2">
          <CadenceTextField
            id="service_identity_display_name"
            v-model="form.display_name"
            name="service_identity[display_name]"
            label="Display name"
            required
            :disabled="disabled"
            :error="errors.display_name"
          /><CadenceTextField
            id="service_identity_id"
            v-model="form.service_identity_id"
            name="service_identity[service_identity_id]"
            label="Custom identity"
            hint="Optional. Leave blank to generate an identity."
            :disabled="disabled"
            :error="errors.service_identity_id"
          />
        </div>
        <p v-if="errors.form" role="alert">{{ errors.form }}</p>
        <p v-if="message" id="service-identity-message" role="alert">{{ message }}</p>
        <button
          id="issue-service-identity"
          type="submit"
          class="btn btn-primary btn-sm"
          :disabled="disabled"
        >
          {{ pending ? "Issuing…" : "Issue service identity" }}
        </button>
        <button
          v-if="uncertain"
          id="refresh-service-identities"
          type="button"
          class="btn btn-sm"
          @click="refresh"
        >
          Refresh status
        </button>
      </form>
    </section>
  </main>
</template>
