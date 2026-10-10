<script setup lang="ts">
import ContactLink from "./ContactLink.vue";
import { computed, inject } from "vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import { CONTACT_RECORD_PORT, type OpsContactRecordProps } from "./OpsContactRecord.contracts";
import { contactPath, recordHref, sectionPage } from "./contact-record";
import { useContactRecord } from "./contact-record-state";
const props = defineProps<OpsContactRecordProps>();
const { record, pending, notice, refresh, connected } = useContactRecord(
  () => props.record,
  props.port ?? inject(CONTACT_RECORD_PORT, undefined),
);
const label = (value: string) => value.replaceAll("_", " ");
useOpsHeader("/missions/:mission_id/ops/contacts/records/:contact_id", () => ({
  title: record.value?.subject.kind === "realized" ? "Realized contact" : "Scheduled contact",
  ...(connected ? { refresh: { run: refresh, pending: pending.value } } : {}),
}));
const pathSections = computed(() =>
  record.value
    ? [
        {
          key: "scheduled_paths" as const,
          title: "Current scheduled paths",
          present: !!record.value.scheduled,
          data: record.value.scheduled_paths,
        },
        {
          key: "realized_paths" as const,
          title: "Realized contact paths",
          present: !!record.value.realized,
          data: record.value.realized_paths,
        },
      ].filter((s) => s.present)
    : [],
);
const contextSections = computed(() =>
  record.value
    ? [
        { key: "sources" as const, title: "Source endpoints", data: record.value.sources },
        { key: "intents" as const, title: "Contact intents", data: record.value.intents },
      ]
    : [],
);
</script>
<template>
  <main v-if="record" id="ops-contact-record-page" class="space-y-6">
    <header class="space-y-3">
      <p id="contact-record-identity" class="break-all text-sm text-base-content/70">
        {{ record.subject.id }}
      </p>
      <p
        v-if="notice"
        id="contact-record-notice"
        role="status"
        class="rounded border border-base-300 bg-base-200 p-3 text-sm"
      >
        {{ notice }}
      </p>
    </header>
    <div class="grid gap-6 lg:grid-cols-2">
      <CadencePanel
        v-if="record.scheduled"
        id="contact-record-schedule"
        class="rounded-lg border border-base-300 bg-base-100 p-5"
        header-class="mb-4"
      >
        <template #header><h2 class="text-lg font-semibold">Current schedule</h2></template>
        <dl class="space-y-3 text-sm">
          <div>
            <dt class="text-base-content/60">Scheduled identity</dt>
            <dd class="break-all">
              <ContactLink
                id="contact-record-scheduled-link"
                :href="contactPath(record, record.scheduled.id)"
                class="text-primary"
                >{{ record.scheduled.id }}</ContactLink
              >
            </dd>
          </div>
          <div>
            <dt class="text-base-content/60">State</dt>
            <dd>
              {{ label(record.scheduled.lifecycle_state) }} · Revision
              {{ record.scheduled.current_revision }}
            </dd>
          </div>
          <div>
            <dt class="text-base-content/60">Current window</dt>
            <dd>
              {{ record.scheduled.starts_at }} – {{ record.scheduled.ends_at ?? "Open-ended" }}
            </dd>
          </div>
          <div v-if="record.scheduled.provider_contact_ref">
            <dt class="text-base-content/60">Provider reference</dt>
            <dd class="break-all">{{ record.scheduled.provider_contact_ref }}</dd>
          </div>
        </dl>
      </CadencePanel>
      <CadencePanel
        v-if="record.realized"
        id="contact-record-realized"
        class="rounded-lg border border-base-300 bg-base-100 p-5"
        header-class="mb-4"
      >
        <template #header><h2 class="text-lg font-semibold">Realized contact</h2></template>
        <dl class="space-y-3 text-sm">
          <div>
            <dt class="text-base-content/60">Realized identity</dt>
            <dd class="break-all">
              <ContactLink
                id="contact-record-realized-link"
                :href="contactPath(record, record.realized.id)"
                class="text-primary"
                >{{ record.realized.id }}</ContactLink
              >
            </dd>
          </div>
          <div>
            <dt class="text-base-content/60">State and clock</dt>
            <dd>{{ label(record.realized.lifecycle_state) }} · {{ record.realized.clock_mode }}</dd>
          </div>
          <div>
            <dt class="text-base-content/60">Realized at</dt>
            <dd>{{ record.realized.realized_at ?? "Not recorded" }}</dd>
          </div>
          <div v-if="record.realized.initial_time">
            <dt class="text-base-content/60">Initial clock time</dt>
            <dd>{{ record.realized.initial_time }}</dd>
          </div>
        </dl>
      </CadencePanel>
    </div>
    <CadencePanel
      v-if="record.review && record.scheduled"
      id="contact-record-review"
      class="rounded-lg border border-base-300 bg-base-100 p-5"
      header-class="mb-4"
    >
      <template #header
        ><h2 class="text-lg font-semibold">
          Reviewed schedule revision {{ record.review.revision }}
        </h2></template
      >
      <div class="space-y-3 text-sm">
        <p id="contact-record-reviewed-window">
          {{ record.review.starts_at }} – {{ record.review.ends_at ?? "Open-ended" }}
        </p>
        <p>
          {{ label(record.review.lifecycle_state) }} when recorded ·
          {{ record.review.created_at }} · {{ record.review.created_by }}
        </p>
        <p class="break-all text-xs text-base-content/60">{{ record.review.id }}</p>
        <p
          v-if="record.review.revision !== record.scheduled.current_revision"
          id="contact-record-historical"
        >
          Historical schedule evidence. The current schedule and realized paths are shown
          separately.
          <ContactLink
            id="contact-record-current-revision"
            class="text-primary"
            :href="
              recordHref(record, {
                revision: record.scheduled.current_revision,
                before_revision: null,
                sources_page: 1,
              })
            "
            >Review current revision</ContactLink
          >
        </p>
        <div
          v-if="record.origin"
          id="contact-record-origin"
          class="space-y-2 rounded border border-base-300 p-3"
        >
          <ContactLink
            id="contact-record-reservation-link"
            class="text-primary"
            :href="`/missions/${encodeURIComponent(record.context.mission_id)}/ops/contacts/${encodeURIComponent(record.origin.reservation_id)}?change_id=${encodeURIComponent(record.origin.change_id)}`"
            >Provider change · Revision {{ record.origin.provider_revision }}</ContactLink
          >
          <p class="break-all font-mono text-xs">{{ record.origin.proposal_hash }}</p>
        </div>
      </div>
    </CadencePanel>
    <p v-else id="contact-record-no-schedule" class="text-sm text-base-content/70">
      This realized contact has no linked schedule. Its execution evidence is shown below.
    </p>
    <CadencePanel
      v-for="section in pathSections"
      :id="`contact-record-${section.key}`"
      :key="section.key"
      class="rounded-lg border border-base-300 bg-base-100 p-5"
      header-class="mb-4"
    >
      <template #header
        ><h2 class="text-lg font-semibold">{{ section.title }}</h2>
        <p v-if="section.key === 'scheduled_paths'" class="mt-1 text-sm text-base-content/60">
          Current revision {{ record.scheduled?.current_revision }}. Historical revision snapshots
          do not contain complete path bindings.
        </p></template
      >
      <div v-if="section.data.entries.length" class="overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead>
            <tr class="border-b border-base-300">
              <th class="p-2">Path</th>
              <th class="p-2">Direction / selection</th>
              <th class="p-2">Source endpoint</th>
              <th class="p-2">Bindings</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="path in section.data.entries"
              :key="path.id"
              class="border-b border-base-300/50"
            >
              <th class="max-w-xs break-all p-2 font-medium">{{ path.id }}</th>
              <td class="p-2">{{ path.direction }} · {{ path.selection }}</td>
              <td class="max-w-xs break-all p-2">{{ path.source_endpoint_ref ?? "Unbound" }}</td>
              <td class="p-2">
                {{ path.provider_binding_count }} provider ·
                {{ path.transport_binding_count }} transport
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else :id="`contact-record-${section.key}-empty`" class="text-sm text-base-content/60">
        No paths on this page.
      </p>
      <nav :aria-label="`${section.title} pages`" class="mt-4 flex gap-4 text-sm text-primary">
        <ContactLink
          v-if="section.data.page > 1"
          :id="`${section.key}-previous`"
          :href="recordHref(record, { [sectionPage(section.key)]: section.data.page - 1 })"
          >Previous</ContactLink
        ><span class="text-base-content/60">Page {{ section.data.page }}</span
        ><ContactLink
          v-if="section.data.more"
          :id="`${section.key}-next`"
          :href="recordHref(record, { [sectionPage(section.key)]: section.data.page + 1 })"
          >Next</ContactLink
        >
      </nav>
    </CadencePanel>
    <div class="grid gap-6 lg:grid-cols-2">
      <CadencePanel
        v-for="section in contextSections"
        :id="`contact-record-${section.key}`"
        :key="section.key"
        class="rounded-lg border border-base-300 bg-base-100 p-5"
        header-class="mb-4"
      >
        <template #header
          ><h2 class="text-lg font-semibold">{{ section.title }}</h2></template
        >
        <ul class="divide-y divide-base-300 text-sm">
          <li v-for="item in section.data.entries" :key="`${item.kind}:${item.id}`" class="py-2">
            <p class="break-all">{{ item.id }}</p>
            <p class="text-xs text-base-content/60">{{ label(item.kind) }}</p>
          </li>
        </ul>
        <p v-if="!section.data.entries.length" class="text-sm text-base-content/60">
          No {{ section.title.toLowerCase() }} on this page.
        </p>
        <nav :aria-label="`${section.title} pages`" class="mt-4 flex gap-4 text-sm text-primary">
          <ContactLink
            v-if="section.data.page > 1"
            :id="`${section.key}-previous`"
            :href="recordHref(record, { [sectionPage(section.key)]: section.data.page - 1 })"
            >Previous</ContactLink
          ><span class="text-base-content/60">Page {{ section.data.page }}</span
          ><ContactLink
            v-if="section.data.more"
            :id="`${section.key}-next`"
            :href="recordHref(record, { [sectionPage(section.key)]: section.data.page + 1 })"
            >Next</ContactLink
          >
        </nav>
      </CadencePanel>
    </div>
    <CadencePanel
      v-if="record.review"
      id="contact-record-revisions"
      class="rounded-lg border border-base-300 bg-base-100 p-5"
      header-class="mb-4"
    >
      <template #header
        ><h2 class="text-lg font-semibold">
          Schedule history through revision {{ record.review.revision }}
        </h2></template
      >
      <ol class="divide-y divide-base-300">
        <li v-for="revision in record.revisions.entries" :key="revision.id" class="py-3 text-sm">
          <ContactLink
            :href="
              recordHref(record, {
                revision: revision.revision,
                before_revision: null,
                sources_page: 1,
              })
            "
            :aria-current="revision.revision === record.review.revision ? 'page' : undefined"
            class="text-primary"
            >Revision {{ revision.revision }}</ContactLink
          >
          <p class="text-xs text-base-content/60">
            {{ revision.created_at }} · {{ revision.created_by }}
          </p>
        </li>
      </ol>
      <p v-if="!record.revisions.entries.length" class="text-sm text-base-content/60">
        No earlier schedule revisions on this page.
      </p>
      <nav
        aria-label="Schedule revision history pages"
        class="mt-4 flex gap-4 text-sm text-primary"
      >
        <ContactLink
          v-if="record.query.before_revision"
          id="contact-revisions-latest"
          :href="recordHref(record, { before_revision: null })"
          >Latest in this review</ContactLink
        ><ContactLink
          v-if="record.revisions.next"
          id="contact-revisions-older"
          :href="recordHref(record, { before_revision: record.revisions.next })"
          >Older revisions</ContactLink
        >
      </nav>
    </CadencePanel>
  </main>
  <div v-else id="contact-record-unavailable" role="alert" class="space-y-3 p-6">
    <h2 class="text-lg font-semibold">Contact record unavailable</h2>
    <p v-if="notice">{{ notice }}</p>
    <button
      id="contact-record-retry"
      type="button"
      :disabled="pending || !connected"
      @click="refresh"
    >
      Refresh evidence
    </button>
  </div>
</template>
