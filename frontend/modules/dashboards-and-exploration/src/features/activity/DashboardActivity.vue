<script setup lang="ts">
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { ActivityState } from "./contracts";
import { useDashboardActivity } from "./useDashboardActivity";
const props = defineProps<{ state: ActivityState; context: OpsPageContext; port: OpsPagePort }>();
const { model, pending, review, notice, execute, base, href, navigate } =
  useDashboardActivity(props);
const label = (value: string) => value.replaceAll("_", " ");
</script>
<template>
  <section id="dashboard-activity-feature" class="space-y-5 p-4 lg:p-6" :aria-busy="pending">
    <header class="flex flex-wrap items-start justify-between gap-4 border-b border-base-300 pb-5">
      <div>
        <p class="font-mono text-xs uppercase tracking-widest text-base-content/60">
          Ops / Version history
        </p>
        <h1 class="mt-2 text-2xl font-semibold">{{ model.name }}</h1>
        <p class="mt-2 text-sm text-base-content/70">
          Latest draft <span class="font-mono">v{{ model.document_version }}</span> · Published
          <span class="font-mono">{{
            model.published_version ? `v${model.published_version}` : "—"
          }}</span
          ><span v-if="model.archived"> · Archived</span
          ><span v-else-if="!model.author"> · Read only</span>
        </p>
      </div>
      <nav aria-label="Dashboard history actions" class="flex flex-wrap gap-2">
        <a
          id="activity-viewer"
          class="btn btn-sm btn-ghost"
          :href="base"
          @click="navigate($event, base)"
          >View dashboard</a
        >
        <a
          v-if="model.author && !model.archived"
          id="activity-editor"
          class="btn btn-sm btn-ghost"
          :href="`${base}/edit`"
          @click="navigate($event, `${base}/edit`)"
          >Edit draft</a
        >
        <button
          id="activity-reload"
          class="btn btn-sm"
          :disabled="pending"
          @click="execute('reload_activity')"
        >
          Reload history
        </button>
      </nav>
    </header>
    <p
      v-if="notice || review"
      id="activity-outcome"
      role="status"
      class="border-l-2 border-warning bg-base-200 p-3 text-sm"
    >
      {{
        pending
          ? "Waiting for confirmation…"
          : notice || "Reload history and review the current versions before making changes."
      }}
    </p>
    <p
      v-if="model.query.issue_id"
      id="activity-issue-notice"
      class="border border-base-300 p-3 text-sm"
    >
      This link references a publication issue. This history view shows version and lifecycle
      metadata, not issue details. Publication readiness is checked again when publishing.
    </p>
    <div class="grid gap-5 lg:grid-cols-[minmax(16rem,1fr)_minmax(0,2fr)]">
      <section
        aria-labelledby="activity-versions-title"
        class="min-w-0 self-start border border-base-300"
      >
        <h2
          id="activity-versions-title"
          class="border-b border-base-300 p-4 text-sm font-semibold uppercase tracking-wide"
        >
          Saved versions
        </h2>
        <ol
          id="activity-versions"
          class="max-h-72 overflow-y-auto divide-y divide-base-300 lg:max-h-[32rem]"
          tabindex="0"
          aria-labelledby="activity-versions-title"
        >
          <li v-for="version in model.versions" :key="version.version">
            <a
              :id="`activity-version-${version.version}`"
              :href="href({ version: version.version })"
              :aria-current="version.version === model.selected.version ? 'true' : undefined"
              class="block border-l-2 p-4 hover:bg-base-200"
              :class="
                version.version === model.selected.version
                  ? 'border-primary bg-primary/5'
                  : 'border-transparent'
              "
              @click="navigate($event, href({ version: version.version }))"
            >
              <span class="flex justify-between gap-2"
                ><span class="font-mono font-semibold">v{{ version.version }}</span
                ><span class="text-xs capitalize text-base-content/60">{{
                  label(version.kind)
                }}</span></span
              >
              <span class="mt-1 block break-words text-sm">{{
                version.summary || "Saved dashboard"
              }}</span>
              <time
                class="mt-2 block break-all font-mono text-xs text-base-content/60"
                :datetime="version.saved_at || undefined"
                >{{ version.saved_at || "Time unavailable" }}</time
              >
            </a>
          </li>
        </ol>
        <p v-if="!model.versions.length" class="p-4 text-sm">No versions on this page.</p>
        <nav
          class="flex flex-wrap gap-4 border-t border-base-300 p-4 text-sm"
          aria-label="Version pages"
        >
          <a
            v-if="model.query.before_version"
            id="activity-latest-versions"
            class="link"
            :href="href({ before_version: null })"
            @click="navigate($event, href({ before_version: null }))"
            >Latest versions</a
          >
          <a
            v-if="model.next_version"
            id="activity-older-versions"
            class="link"
            :href="href({ before_version: model.next_version })"
            @click="navigate($event, href({ before_version: model.next_version }))"
            >Older versions →</a
          >
        </nav>
      </section>
      <div class="min-w-0 space-y-5">
        <section
          id="activity-selected"
          aria-labelledby="activity-selected-title"
          class="border border-base-300 p-5"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 id="activity-selected-title" class="text-lg font-semibold">
              Version {{ model.selected.version }}
            </h2>
            <span class="font-mono text-xs text-base-content/60"
              >Schema {{ model.selected.schema_version }}</span
            >
          </div>
          <p class="mt-3">{{ model.selected.name }}</p>
          <p class="mt-1 text-sm text-base-content/70">
            {{ model.selected.summary || "Saved dashboard" }}
          </p>
          <dl class="my-5 grid grid-cols-2 gap-4 border-y border-base-300 py-4 text-sm">
            <div>
              <dt class="text-base-content/60">Widgets</dt>
              <dd class="font-mono">{{ model.selected.widget_count }}</dd>
            </div>
            <div>
              <dt class="text-base-content/60">Sections</dt>
              <dd class="font-mono">{{ model.selected.section_count }}</dd>
            </div>
            <div>
              <dt class="text-base-content/60">Parent version</dt>
              <dd class="font-mono">{{ model.selected.parent_version ?? "—" }}</dd>
            </div>
            <div>
              <dt class="text-base-content/60">Based on version</dt>
              <dd class="font-mono">{{ model.selected.based_on_version ?? "—" }}</dd>
            </div>
          </dl>
          <p class="break-all text-xs text-base-content/60">
            Saved by {{ model.selected.actor_id || "System / unavailable" }} ·
            <time :datetime="model.selected.saved_at || undefined">{{
              model.selected.saved_at || "Time unavailable"
            }}</time>
          </p>
          <p class="mt-5 border-t border-base-300 pt-5 text-sm text-base-content/70">
            Every save is the current version. To compare or restore versions, open
            <a :href="base" class="text-primary hover:underline">the dashboard</a> and choose
            Versions.
          </p>
        </section>
        <section aria-labelledby="activity-events-title" class="border border-base-300">
          <h2
            id="activity-events-title"
            class="border-b border-base-300 p-4 text-sm font-semibold uppercase tracking-wide"
          >
            Lifecycle activity
          </h2>
          <ol
            id="activity-events"
            class="max-h-80 overflow-y-auto divide-y divide-base-300 lg:max-h-[28rem]"
            tabindex="0"
            aria-labelledby="activity-events-title"
          >
            <li v-for="event in model.events" :key="event.id" class="p-4 text-sm">
              <div class="flex flex-wrap justify-between gap-2">
                <span class="capitalize">{{ label(event.event_type) }}</span
                ><span v-if="event.document_version" class="font-mono text-xs"
                  >v{{ event.document_version }}</span
                >
              </div>
              <p class="mt-2 break-all text-xs text-base-content/60">
                <time :datetime="event.occurred_at || undefined">{{
                  event.occurred_at || "Time unavailable"
                }}</time>
                · {{ event.actor_id || "System / unavailable" }}
              </p>
            </li>
          </ol>
          <p v-if="!model.events.length" class="p-4 text-sm text-base-content/60">
            No lifecycle events on this page.
          </p>
          <nav
            class="flex flex-wrap gap-4 border-t border-base-300 p-4 text-sm"
            aria-label="Activity pages"
          >
            <a
              v-if="model.query.before_event"
              id="activity-latest-events"
              class="link"
              :href="href({ before_event: null })"
              @click="navigate($event, href({ before_event: null }))"
              >Latest activity</a
            ><a
              v-if="model.next_event"
              id="activity-older-events"
              class="link"
              :href="href({ before_event: model.next_event })"
              @click="navigate($event, href({ before_event: model.next_event }))"
              >Older activity →</a
            >
          </nav>
        </section>
      </div>
    </div>
  </section>
</template>
