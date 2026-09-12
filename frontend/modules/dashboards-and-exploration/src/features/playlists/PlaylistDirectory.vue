<script setup lang="ts">
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { DirectoryState } from "./contracts";
import { usePlaylistAuthoring } from "./usePlaylistAuthoring";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ state: DirectoryState; context: OpsPageContext; port: OpsPagePort }>();
const {
  model,
  draft,
  queue,
  choices,
  dirty,
  pending,
  notice,
  receipt,
  disabled,
  searchText,
  searching,
  searchError,
  collectionQuery,
  add,
  remove,
  move,
  search,
  execute,
  base,
  href,
  go,
  navigate,
} = usePlaylistAuthoring(props);
const present = (id: string) => `${base.value}/playlists/${encodeURIComponent(id)}/present`;
</script>
<template>
  <section id="playlist-directory-feature" class="space-y-5 p-4 lg:p-6" :aria-busy="pending">
    <header class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 pb-4">
      <div>
        <p class="hud-label">Ops / Dashboard rotation</p>
        <h2 class="mt-2 text-xl font-semibold">Playlists</h2>
        <p class="mt-2 text-sm text-base-content/60">
          Ordered references. Published dashboards. Explicit unavailable entries.
        </p>
      </div>
      <div class="flex gap-2">
        <a
          id="playlist-directory-dashboard-link"
          :href="base"
          class="btn btn-ghost btn-sm"
          @click="navigate($event, base)"
          >Dashboards</a
        ><button
          id="playlist-reload"
          class="btn btn-sm"
          :disabled="pending"
          @click="execute('reload_playlists')"
        >
          Reload playlists
        </button>
      </div>
    </header>
    <div
      v-if="notice"
      id="playlist-outcome"
      role="status"
      class="border-l-2 border-warning p-3 text-sm"
    >
      {{ notice }}
      <a
        v-if="receipt"
        id="playlist-created-link"
        :href="present(receipt.id)"
        class="ml-2 underline"
        @click="navigate($event, present(receipt.id))"
        >Present {{ receipt.name }}</a
      >
    </div>
    <div class="grid gap-5 xl:grid-cols-[minmax(16rem,1fr)_minmax(0,2fr)]">
      <section aria-labelledby="playlist-saved-title" class="min-w-0 border border-base-300 p-4">
        <h3 id="playlist-saved-title" class="hud-label">Saved playlists</h3>
        <form id="playlist-filter-form" class="my-4 flex gap-2" @submit.prevent="go(href())">
          <label class="min-w-0 flex-1"
            ><span class="sr-only">Search playlists</span
            ><input
              id="playlist-filter"
              v-model="collectionQuery"
              class="input input-bordered input-sm w-full"
              maxlength="120" /></label
          ><button class="btn btn-sm" :disabled="pending">Search</button>
        </form>
        <ul id="playlist-saved-list" class="max-h-96 space-y-3 overflow-y-auto">
          <li
            v-for="item in model.playlists.rows"
            :key="item.id"
            class="border border-base-300 p-3"
          >
            <a
              :data-playlist-id="item.id"
              :href="present(item.id)"
              class="break-words font-semibold text-primary"
              @click="navigate($event, present(item.id))"
              >{{ item.name }}</a
            >
            <p class="mt-1 break-words text-xs text-base-content/60">{{ item.description }}</p>
            <p class="mt-2 font-mono text-xs">
              {{ item.count }} entries · {{ item.dwell_seconds }}s ·
              {{ item.wallboard_mode ? "Wallboard" : "Manual start" }}
            </p>
          </li>
        </ul>
        <p
          v-if="!model.playlists.rows.length"
          id="playlist-empty"
          class="py-6 text-sm text-base-content/60"
        >
          No matching playlists.
        </p>
        <nav class="mt-4 flex gap-3 text-sm">
          <a
            v-if="model.query.after"
            :href="href(model.query.q)"
            @click="navigate($event, href(model.query.q))"
            >First page</a
          ><a
            v-if="model.playlists.next"
            id="playlist-more"
            :href="href(model.query.q, model.playlists.next)"
            @click="navigate($event, href(model.query.q, model.playlists.next))"
            >More playlists</a
          >
        </nav>
      </section>
      <section
        class="min-w-0 space-y-4 border border-base-300 p-4"
        aria-labelledby="playlist-author-title"
      >
        <div class="flex flex-wrap justify-between gap-2">
          <h3 id="playlist-author-title" class="font-semibold">Build an ordered queue</h3>
          <span id="playlist-dirty" class="font-mono text-xs text-base-content/60">{{
            dirty ? "Unsaved playlist" : "No unsaved changes"
          }}</span>
        </div>
        <form id="playlist-choice-search" class="flex gap-2" @submit.prevent="search()">
          <label class="min-w-0 flex-1"
            ><span class="block text-xs text-base-content/60">Find active dashboards</span
            ><input
              id="playlist-choice-query"
              v-model="searchText"
              class="input input-bordered input-sm w-full"
              maxlength="120" /></label
          ><button
            id="playlist-choice-submit"
            class="btn btn-sm self-end"
            :disabled="searching || pending"
          >
            Search
          </button>
        </form>
        <p v-if="searchError" id="playlist-search-error" role="status" class="text-sm text-warning">
          {{ searchError }}
        </p>
        <ul id="playlist-choices" class="max-h-52 overflow-y-auto border border-base-300">
          <li
            v-for="choice in choices.rows"
            :key="choice.id"
            class="flex items-center justify-between gap-3 border-b border-base-300 p-2"
          >
            <div class="min-w-0">
              <p class="break-words text-sm">{{ choice.name }}</p>
              <p class="font-mono text-xs text-base-content/60">
                {{
                  choice.published_version
                    ? `Published v${choice.published_version}`
                    : "Not published"
                }}
              </p>
            </div>
            <button
              :data-add-dashboard="choice.id"
              class="btn btn-xs shrink-0"
              :disabled="disabled || queue.length >= 100"
              @click="add(choice)"
            >
              Add
            </button>
          </li>
        </ul>
        <button
          v-if="choices.next"
          id="playlist-more-choices"
          class="btn btn-xs"
          :disabled="searching || pending"
          @click="search(choices.next)"
        >
          More dashboards
        </button>
        <p class="text-xs text-base-content/60">
          Up to 100 entries. Repeated dashboards are allowed. Unpublished or archived entries stay
          visible as unavailable during presentation.
        </p>
        <ol id="playlist-queue" class="max-h-72 space-y-2 overflow-y-auto">
          <li
            v-for="(entry, index) in queue"
            :key="entry.key"
            tabindex="-1"
            class="flex flex-wrap items-center gap-2 border border-primary/20 bg-primary/5 p-2"
          >
            <span class="font-mono text-xs">{{ String(index + 1).padStart(2, "0") }}</span
            ><span class="min-w-0 flex-1 break-words text-sm">{{ entry.name }}</span
            ><button
              :aria-label="`Move entry ${index + 1} up`"
              class="btn btn-xs"
              :disabled="disabled || index === 0"
              @click="move(index, -1, $event)"
            >
              Up</button
            ><button
              :aria-label="`Move entry ${index + 1} down`"
              class="btn btn-xs"
              :disabled="disabled || index === queue.length - 1"
              @click="move(index, 1, $event)"
            >
              Down</button
            ><button
              :aria-label="`Remove entry ${index + 1}`"
              class="btn btn-ghost btn-xs"
              :disabled="disabled"
              @click="remove(index)"
            >
              Remove
            </button>
          </li>
        </ol>
        <form id="playlist-create-form" @submit.prevent="execute('create_playlist')">
          <fieldset :disabled="disabled" class="space-y-3">
            <label class="block text-sm"
              >Name<input
                id="playlist-name"
                v-model="draft.name"
                required
                maxlength="120"
                class="input input-bordered mt-1 w-full" /></label
            ><label class="block text-sm"
              >Description<textarea
                id="playlist-description"
                v-model="draft.description"
                maxlength="4096"
                class="textarea textarea-bordered mt-1 w-full"
              />
            </label>
            <div class="flex flex-wrap items-end gap-4">
              <label class="text-sm"
                >Seconds per dashboard<input
                  id="playlist-dwell"
                  v-model.number="draft.dwell_seconds"
                  type="number"
                  min="5"
                  max="900"
                  step="1"
                  required
                  class="input input-bordered mt-1 block w-28" /></label
              ><label class="flex items-center gap-2 pb-2 text-sm"
                ><input
                  id="playlist-wallboard"
                  v-model="draft.wallboard_mode"
                  type="checkbox"
                  class="checkbox checkbox-sm"
                />Start rotation automatically</label
              >
            </div>
            <button
              id="playlist-create"
              class="btn btn-primary btn-sm"
              :disabled="disabled || !queue.length"
            >
              Create playlist
            </button>
          </fieldset>
        </form>
      </section>
    </div>
  </section>
</template>
