<script setup lang="ts">
import {
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuRoot,
  DropdownMenuTrigger
} from "reka-ui"
import StatusBadge from "./StatusBadge.vue"

type Status = "ready" | "attention"

type SummaryTile = {
  id: string
  label: string
  value: number
  href: string
  active: boolean
  warning: boolean
}

type SpacecraftRow = {
  id: string
  actions_id: string
  display_name: string
  scid_label: string
  scid_missing: boolean
  profile_label: string
  status: Status
  status_label: string
  href: string
  identity_href: string
}

type Roster = {
  fleet_empty: boolean
  subtitle: string
  new_spacecraft_href: string
  search: string
  sort_by: "display_name" | "scid"
  sort_dir: "asc" | "desc"
  filtered_empty: boolean
  page: number
  page_size: number
  total_count: number
  pagination_visible: boolean
  range_label: string
  previous_page: number
  next_page: number
  previous_disabled: boolean
  next_disabled: boolean
  rows: SpacecraftRow[]
}

type FleetEntry = {
  label: string
  href: string | null
}

type ProfileRow = {
  id: string
  display_name: string
  href: string
  fleet_entries: FleetEntry[]
  protocols: string
  applications: string
  status: Status
  status_label: string
}

type Profiles = {
  empty: boolean
  truncated: boolean
  subtitle: string
  new_profile_href: string
  all_profiles_href: string
  rows: ProfileRow[]
}

defineProps<{
  summary_tiles: SummaryTile[]
  roster: Roster
  profiles: Profiles
}>()
</script>

<template>
  <div id="spacecraft-list-content" class="space-y-6">
    <div id="spacecraft-setup-summary" class="grid gap-3 md:grid-cols-4">
      <a
        v-for="tile in summary_tiles"
        :id="tile.id"
        :key="tile.id"
        :href="tile.href"
        data-phx-link="patch"
        data-phx-link-state="push"
        :aria-current="tile.active ? 'true' : undefined"
        class="block border bg-base-200 px-3 py-2 transition-colors"
        :class="[
          tile.active
            ? 'border-primary/60'
            : 'border-base-300 hover:border-primary/40',
          tile.warning && 'border-l-2 border-l-warning/60'
        ]"
      >
        <p class="hud-label" :class="tile.active && 'text-primary!'">{{ tile.label }}</p>
        <p class="mt-1 font-mono text-xl text-base-content">{{ tile.value }}</p>
      </a>
    </div>

    <section id="spacecraft-vehicles-card" class="card border border-base-300 bg-base-200">
      <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">
        <div>
          <h2 class="text-base font-semibold text-base-content">Vehicles</h2>
          <p class="mt-1 text-xs text-base-content/70">{{ roster.subtitle }}</p>
        </div>
        <div class="flex items-center gap-2">
          <a
            :href="roster.new_spacecraft_href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-primary btn-sm gap-1"
          >
            <span class="hero-plus h-4 w-4"></span> New spacecraft
          </a>
        </div>
      </div>

      <div class="card-body" :class="roster.fleet_empty ? 'p-6' : 'p-0'">
        <div
          v-if="roster.fleet_empty"
          class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        >
          <p class="hud-label">No spacecraft yet</p>
          <p class="mx-auto mt-2 max-w-md text-sm text-base-content/70">
            Register the first spacecraft for this mission.
          </p>
          <div class="mt-5">
            <a
              :href="roster.new_spacecraft_href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-primary btn-sm"
            >
              <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>
              Register the first spacecraft
            </a>
          </div>
        </div>

        <template v-else>
          <div
            id="spacecraft-roster-toolbar"
            class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-2"
          >
            <form
              id="spacecraft-roster-toolbar-search-form"
              phx-change="search"
              class="w-64 max-w-full"
              @submit.prevent
            >
              <div class="fieldset">
                <label>
                  <input
                    id="spacecraft-roster-toolbar-search"
                    name="q"
                    type="search"
                    :value="roster.search"
                    placeholder="Search name or SCID"
                    class="input input-sm w-full"
                    phx-debounce="300"
                  />
                </label>
              </div>
            </form>
          </div>

          <table id="spacecraft-vehicles-table" class="table">
            <thead>
              <tr>
                <th
                  class="hud-label"
                  :aria-sort="roster.sort_by === 'display_name' ? `${roster.sort_dir}ending` : undefined"
                >
                  <button
                    type="button"
                    phx-click="sort"
                    phx-value-sort="display_name"
                    class="inline-flex cursor-pointer items-center gap-1 uppercase hover:text-primary"
                  >
                    Name
                    <span
                      v-if="roster.sort_by === 'display_name'"
                      class="h-3 w-3"
                      :class="roster.sort_dir === 'asc' ? 'hero-chevron-up' : 'hero-chevron-down'"
                    ></span>
                  </button>
                </th>
                <th
                  class="hud-label"
                  :aria-sort="roster.sort_by === 'scid' ? `${roster.sort_dir}ending` : undefined"
                >
                  <button
                    type="button"
                    phx-click="sort"
                    phx-value-sort="scid"
                    class="inline-flex cursor-pointer items-center gap-1 uppercase hover:text-primary"
                  >
                    SCID
                    <span
                      v-if="roster.sort_by === 'scid'"
                      class="h-3 w-3"
                      :class="roster.sort_dir === 'asc' ? 'hero-chevron-up' : 'hero-chevron-down'"
                    ></span>
                  </button>
                </th>
                <th class="hud-label">Profile</th>
                <th class="hud-label">Setup</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
            </thead>
            <tbody id="spacecraft-vehicles">
              <tr
                v-for="row in roster.rows"
                :id="row.id"
                :key="row.id"
                class="border-l-2 border-l-transparent transition-colors hover:border-l-primary/60"
              >
                <td class="font-medium">
                  <a
                    :href="row.href"
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="text-primary hover:underline"
                  >{{ row.display_name }}</a>
                </td>
                <td class="font-mono text-sm">
                  <span :class="row.scid_missing ? 'text-base-content/50 italic' : 'text-base-content'">
                    {{ row.scid_label }}
                  </span>
                </td>
                <td class="text-sm text-base-content/70">{{ row.profile_label }}</td>
                <td>
                  <StatusBadge :status="row.status" :label="row.status_label" />
                </td>
                <td class="text-right">
                  <div :id="row.actions_id">
                    <DropdownMenuRoot>
                      <DropdownMenuTrigger as-child>
                        <button
                          :id="`${row.actions_id}-trigger`"
                          class="btn btn-ghost btn-xs"
                          type="button"
                          aria-label="Actions"
                        >
                          <span class="hero-ellipsis-vertical h-5 w-5"></span>
                        </button>
                      </DropdownMenuTrigger>
                      <DropdownMenuPortal>
                        <DropdownMenuContent
                          :id="`${row.actions_id}-menu`"
                          class="z-50 min-w-40 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
                          side="bottom"
                          align="end"
                          :side-offset="4"
                        >
                          <DropdownMenuItem as-child>
                            <a
                              :href="row.href"
                              data-phx-link="redirect"
                              data-phx-link-state="push"
                              class="block cursor-pointer rounded px-3 py-2 text-sm outline-none hover:bg-base-200"
                            >View</a>
                          </DropdownMenuItem>
                          <DropdownMenuItem as-child>
                            <a
                              :href="row.identity_href"
                              data-phx-link="redirect"
                              data-phx-link-state="push"
                              class="block cursor-pointer rounded px-3 py-2 text-sm outline-none hover:bg-base-200"
                            >Identity</a>
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenuPortal>
                    </DropdownMenuRoot>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>

          <p
            v-if="roster.filtered_empty"
            class="py-6 text-center text-sm text-base-content/70"
          >
            No spacecraft match the current search or filter.
          </p>

          <div
            v-if="roster.pagination_visible"
            id="spacecraft-roster-pagination"
            class="flex items-center justify-between border-t border-base-300 px-4 py-2"
          >
            <span class="font-mono text-xs text-base-content/70">{{ roster.range_label }}</span>
            <div class="flex items-center gap-1">
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="paginate"
                :phx-value-page="roster.previous_page"
                :disabled="roster.previous_disabled"
              >Prev</button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="paginate"
                :phx-value-page="roster.next_page"
                :disabled="roster.next_disabled"
              >Next</button>
            </div>
          </div>
        </template>
      </div>
    </section>

    <section id="spacecraft-profiles-card" class="card border border-base-300 bg-base-200">
      <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">
        <div>
          <h2 class="text-base font-semibold text-base-content">Profiles</h2>
          <p class="mt-1 text-xs text-base-content/70">{{ profiles.subtitle }}</p>
        </div>
        <div class="flex items-center gap-2">
          <a
            :href="profiles.new_profile_href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-primary btn-sm gap-1"
          >
            <span class="hero-plus h-4 w-4"></span> New profile
          </a>
        </div>
      </div>

      <div class="card-body" :class="profiles.empty ? 'p-6' : 'p-0'">
        <div
          v-if="profiles.empty"
          class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        >
          <p class="hud-label">No profiles yet</p>
          <p class="mx-auto mt-2 max-w-md text-sm text-base-content/70">
            Create a profile to reuse frame and packet interpretation settings across spacecraft.
          </p>
          <div class="mt-5">
            <a
              :href="profiles.new_profile_href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-primary btn-sm"
            >
              <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>
              Create the first profile
            </a>
          </div>
        </div>

        <template v-else>
          <table id="spacecraft-profiles-preview-table" class="table">
            <thead>
              <tr>
                <th class="hud-label">Name</th>
                <th class="hud-label">Fleet</th>
                <th class="hud-label">Protocols</th>
                <th class="hud-label">Applications</th>
                <th class="hud-label">State</th>
              </tr>
            </thead>
            <tbody id="spacecraft-profile-previews">
              <tr
                v-for="row in profiles.rows"
                :id="row.id"
                :key="row.id"
                class="border-l-2 border-l-transparent transition-colors hover:border-l-primary/60"
              >
                <td class="font-medium">
                  <a
                    :href="row.href"
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="text-primary hover:underline"
                  >{{ row.display_name }}</a>
                </td>
                <td class="font-mono text-sm text-base-content/70">
                  <template v-if="row.fleet_entries.length === 0">
                    <span class="text-base-content/50">Unused</span>
                  </template>
                  <template v-else>
                    <template v-for="(entry, index) in row.fleet_entries" :key="entry.label">
                      <span v-if="index > 0" class="text-base-content/40">·</span>
                      <a
                        v-if="entry.href"
                        :href="entry.href"
                        data-phx-link="patch"
                        data-phx-link-state="push"
                        class="text-warning hover:underline"
                      >{{ entry.label }}</a>
                      <span v-else>{{ entry.label }}</span>
                    </template>
                  </template>
                </td>
                <td class="font-mono text-sm uppercase text-base-content/70">{{ row.protocols }}</td>
                <td class="text-sm text-base-content/70">{{ row.applications }}</td>
                <td>
                  <StatusBadge :status="row.status" :label="row.status_label" />
                </td>
              </tr>
            </tbody>
          </table>

          <div v-if="profiles.truncated" class="border-t border-base-300 px-4 py-3 text-right">
            <a
              :href="profiles.all_profiles_href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-ghost btn-sm"
            >View all profiles</a>
          </div>
        </template>
      </div>
    </section>
  </div>
</template>
