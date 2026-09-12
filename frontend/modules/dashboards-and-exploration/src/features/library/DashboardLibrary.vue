<script setup lang="ts">
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { LibraryState } from "./contracts";
import LibraryDefinitionForm from "./LibraryDefinitionForm.vue";
import { useDashboardLibrary } from "./useDashboardLibrary";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ state: LibraryState; context: OpsPageContext; port: OpsPagePort }>();
const {
  model,
  pending,
  review,
  notice,
  jsonError,
  mode,
  draft,
  dirty,
  disabled,
  receipt,
  query,
  dashboardQuery,
  changeMode,
  execute,
  base,
  href,
  navigate,
  go,
  selectTarget,
} = useDashboardLibrary(props);
const selectItem = (id: string) => ({
  item_id: id,
  version: null,
  before_version: null,
  consumer_after: null,
});
</script>
<template>
  <section id="dashboard-library-feature" class="space-y-5 p-4 lg:p-6" :aria-busy="pending">
    <header class="flex flex-wrap items-start justify-between gap-4 border-b border-base-300 pb-5">
      <div>
        <p class="font-mono text-xs uppercase tracking-widest text-base-content/60">
          Ops / Reusable widgets
        </p>
        <h1 class="mt-2 text-2xl font-semibold">Dashboard library</h1>
        <p class="mt-2 text-sm text-base-content/70">
          Immutable definitions. Explicit pins. Independent dashboard drafts.
        </p>
      </div>
      <nav aria-label="Library navigation" class="flex gap-2">
        <a
          id="library-directory"
          class="btn btn-sm btn-ghost"
          :href="base"
          @click="navigate($event, base)"
          >Dashboards</a
        ><button
          id="library-reload"
          class="btn btn-sm"
          :disabled="pending"
          @click="execute('reload_library')"
        >
          Reload library
        </button>
      </nav>
    </header>
    <div
      v-if="notice || review"
      id="library-outcome"
      role="status"
      class="border-l-2 border-warning bg-base-200 p-3 text-sm"
    >
      <p>
        {{
          pending
            ? "Waiting for confirmation…"
            : notice || "Reload the library and review saved versions before another change."
        }}
      </p>
      <a
        v-if="receipt"
        id="library-saved-item"
        class="link mt-2 inline-block"
        :href="href({ ...selectItem(receipt.item_id), version: receipt.library_version })"
        @click="
          navigate(
            $event,
            href({ ...selectItem(receipt.item_id), version: receipt.library_version }),
          )
        "
        >Open saved widget v{{ receipt.library_version }}</a
      ><a
        v-if="receipt?.dashboard_id"
        id="library-saved-dashboard"
        class="link ml-4 inline-block"
        :href="`${base}/${encodeURIComponent(receipt.dashboard_id)}/edit`"
        @click="navigate($event, `${base}/${encodeURIComponent(receipt.dashboard_id)}/edit`)"
        >Open draft v{{ receipt.document_version }}</a
      >
    </div>
    <div class="grid items-start gap-5 xl:grid-cols-[18rem_minmax(0,1fr)]">
      <section class="min-w-0 border border-base-300" aria-labelledby="library-items-title">
        <h2
          id="library-items-title"
          class="border-b border-base-300 p-4 text-sm font-semibold uppercase tracking-wide"
        >
          Reusable widgets
        </h2>
        <form
          id="library-search-form"
          class="space-y-2 p-4"
          @submit.prevent="go({ q: query, after: null })"
        >
          <label for="library-search" class="text-xs text-base-content/60"
            >Search widget names</label
          >
          <div class="flex gap-2">
            <input
              id="library-search"
              v-model="query"
              class="input input-sm min-w-0 flex-1"
              maxlength="120"
              :disabled="pending"
            /><button id="library-search-submit" class="btn btn-sm" :disabled="pending">
              Search
            </button>
          </div>
        </form>
        <ul
          id="library-items"
          class="max-h-72 divide-y divide-base-300 overflow-y-auto xl:max-h-[36rem]"
          tabindex="0"
          aria-labelledby="library-items-title"
        >
          <li v-for="item in model.items" :key="item.id">
            <a
              :data-library-item="item.id"
              :href="href(selectItem(item.id))"
              class="block border-l-2 p-4 hover:bg-base-200"
              :class="
                item.id === model.selected?.item.id
                  ? 'border-primary bg-primary/5'
                  : 'border-transparent'
              "
              :aria-current="item.id === model.selected?.item.id ? 'true' : undefined"
              @click="navigate($event, href(selectItem(item.id)))"
              ><span class="flex justify-between gap-2"
                ><span class="break-words font-semibold">{{ item.name }}</span
                ><span class="font-mono text-xs">v{{ item.latest_version }}</span></span
              ><span class="mt-2 block break-words text-xs text-base-content/60">{{
                item.description
              }}</span></a
            >
          </li>
        </ul>
        <p v-if="!model.items.length" id="library-empty" class="p-4 text-sm text-base-content/60">
          No reusable widgets match this search.
        </p>
        <nav class="flex gap-4 border-t border-base-300 p-4 text-sm" aria-label="Library pages">
          <a
            v-if="model.query.after"
            id="library-first-page"
            class="link"
            :href="href({ after: null })"
            @click="navigate($event, href({ after: null }))"
            >First page</a
          ><a
            v-if="model.next_item"
            id="library-next-page"
            class="link"
            :href="href({ after: model.next_item })"
            @click="navigate($event, href({ after: model.next_item }))"
            >More widgets →</a
          >
        </nav>
      </section>
      <div class="min-w-0 space-y-5">
        <section
          v-if="model.selected"
          id="library-selected"
          class="space-y-4 border border-base-300 p-4"
        >
          <header class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 id="library-selected-name" class="text-lg font-semibold">
              {{ model.selected.item.name }}
            </h2>
            <span id="library-selected-version" class="font-mono text-xs"
              >Selected v{{ model.selected.version }} · Latest v{{
                model.selected.item.latest_version
              }}</span
            >
          </header>
          <p class="text-sm text-base-content/70">{{ model.selected.item.description }}</p>
          <details id="library-saved-definition" class="border-y border-base-300 py-3">
            <summary class="cursor-pointer text-sm">Inspect saved definition</summary>
            <pre class="mt-3 max-h-72 overflow-auto bg-base-200 p-3 font-mono text-xs">{{
              model.selected.widget_json
            }}</pre>
          </details>
          <h3 class="text-xs font-semibold uppercase tracking-wide">Immutable version history</h3>
          <ol id="library-versions" class="max-h-48 space-y-2 overflow-y-auto">
            <li
              v-for="version in model.selected.versions"
              :key="version.version"
              class="flex flex-wrap items-baseline gap-2 text-sm"
            >
              <a
                :data-library-version="version.version"
                class="link font-mono"
                :href="href({ version: version.version })"
                :aria-current="model.selected.version === version.version ? 'true' : undefined"
                @click="navigate($event, href({ version: version.version }))"
                >v{{ version.version }}</a
              ><span class="break-words">{{ version.summary || "Saved widget" }}</span
              ><span class="break-all text-xs text-base-content/60"
                >{{ version.actor_id || "System / unavailable" }} ·
                {{ version.saved_at || "Time unavailable" }}</span
              >
            </li>
          </ol>
          <nav class="flex gap-4 text-sm" aria-label="Library version pages">
            <a
              v-if="model.query.before_version"
              id="library-latest-versions"
              class="link"
              :href="href({ before_version: null })"
              @click="navigate($event, href({ before_version: null }))"
              >Latest versions</a
            ><a
              v-if="model.selected.next_version"
              id="library-older-versions"
              class="link"
              :href="href({ before_version: model.selected.next_version })"
              @click="navigate($event, href({ before_version: model.selected.next_version }))"
              >Older versions →</a
            >
          </nav>
          <section
            class="space-y-3 border-t border-base-300 pt-4"
            aria-labelledby="library-consumers-title"
          >
            <h3 id="library-consumers-title" class="text-xs font-semibold uppercase tracking-wide">
              Current-draft consumer dashboards · {{ model.selected.consumers.total }}
            </h3>
            <p class="text-xs text-base-content/60">
              Pins below describe active dashboard drafts, not their published versions. New library
              versions never change these pins automatically.
            </p>
            <ul id="library-consumers" class="max-h-64 space-y-3 overflow-y-auto">
              <li
                v-for="consumer in model.selected.consumers.rows"
                :key="consumer.id"
                class="border border-base-300 p-3 text-sm"
              >
                <a
                  :data-library-consumer="consumer.id"
                  class="link"
                  :href="`${base}/${encodeURIComponent(consumer.id)}/edit`"
                  @click="navigate($event, `${base}/${encodeURIComponent(consumer.id)}/edit`)"
                  >{{ consumer.name }}</a
                >
                <p class="mt-1 font-mono text-xs text-base-content/60">
                  Draft v{{ consumer.version ?? "?" }}
                </p>
                <ul class="mt-2 space-y-1">
                  <li v-for="pin in consumer.pins" :key="pin.id" class="break-all text-xs">
                    {{ pin.id }} · pinned v{{ pin.version
                    }}<span
                      v-if="pin.version < model.selected.item.latest_version"
                      class="text-warning"
                    >
                      · newer version available</span
                    >
                  </li>
                </ul>
              </li>
            </ul>
            <p v-if="!model.selected.consumers.rows.length" class="text-sm text-base-content/60">
              No consumer dashboards on this page.
            </p>
            <nav class="flex gap-4 text-sm" aria-label="Consumer pages">
              <a
                v-if="model.query.consumer_after"
                id="library-first-consumers"
                class="link"
                :href="href({ consumer_after: null })"
                @click="navigate($event, href({ consumer_after: null }))"
                >First consumers</a
              ><a
                v-if="model.selected.consumers.next"
                id="library-more-consumers"
                class="link"
                :href="href({ consumer_after: model.selected.consumers.next })"
                @click="navigate($event, href({ consumer_after: model.selected.consumers.next }))"
                >More consumers →</a
              >
            </nav>
          </section>
        </section>
        <div class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(16rem,0.75fr)]">
          <LibraryDefinitionForm
            :mode="mode"
            :selected="!!model.selected"
            :latest="model.selected?.item.latest_version"
            :draft="draft"
            :disabled="disabled"
            :dirty="dirty"
            :json-error="jsonError"
            @mode="changeMode"
            @save="execute(mode)"
          />
          <section
            id="library-draft-target"
            class="space-y-4 border border-primary/30 bg-primary/5 p-4"
            aria-labelledby="library-target-title"
          >
            <h2 id="library-target-title" class="font-semibold">Add selected version to a draft</h2>
            <p class="text-sm text-base-content/70">
              Adds a new placement pinned to this exact library version. Existing placements and
              publication stay unchanged.
            </p>
            <form
              id="library-dashboard-search-form"
              class="space-y-2"
              @submit.prevent="go({ dashboard_query: dashboardQuery, dashboard_after: null })"
            >
              <label for="library-dashboard-search" class="text-sm">Search dashboard names</label>
              <div class="flex gap-2">
                <input
                  id="library-dashboard-search"
                  v-model="dashboardQuery"
                  class="input input-sm min-w-0 flex-1"
                  maxlength="120"
                  :disabled="pending"
                /><button
                  id="library-dashboard-search-submit"
                  class="btn btn-sm"
                  :disabled="pending"
                >
                  Search
                </button>
              </div>
            </form>
            <div>
              <label for="library-target" class="mb-1 block text-sm">Target dashboard</label
              ><select
                id="library-target"
                class="select w-full"
                :value="model.target?.id || ''"
                :disabled="disabled"
                @change="selectTarget"
              >
                <option value="">Choose a dashboard</option>
                <option
                  v-if="model.target && !model.dashboards.some((d) => d.id === model.target!.id)"
                  :value="model.target.id"
                >
                  {{ model.target.name }}
                </option>
                <option
                  v-for="dashboard in model.dashboards"
                  :key="dashboard.id"
                  :value="dashboard.id"
                >
                  {{ dashboard.name }}
                </option>
              </select>
            </div>
            <nav class="flex gap-4 text-sm" aria-label="Target dashboard pages">
              <a
                v-if="model.query.dashboard_after"
                id="library-first-dashboards"
                class="link"
                :href="href({ dashboard_after: null })"
                @click="navigate($event, href({ dashboard_after: null }))"
                >First dashboards</a
              ><a
                v-if="model.next_dashboard"
                id="library-more-dashboards"
                class="link"
                :href="href({ dashboard_after: model.next_dashboard })"
                @click="navigate($event, href({ dashboard_after: model.next_dashboard }))"
                >More dashboards →</a
              >
            </nav>
            <p
              v-if="model.target && model.selected"
              id="library-pin-summary"
              class="font-mono text-xs"
            >
              Library v{{ model.selected.version }} → {{ model.target.name }} · observed draft v{{
                model.target.version
              }}
            </p>
            <button
              id="library-add-to-draft"
              class="btn btn-sm btn-primary"
              :disabled="disabled || !model.selected || !model.target"
              @click="execute('add_to_draft')"
            >
              Add to draft
            </button>
          </section>
        </div>
      </div>
    </div>
  </section>
</template>
