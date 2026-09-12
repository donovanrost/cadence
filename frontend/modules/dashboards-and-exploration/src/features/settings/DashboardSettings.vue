<script setup lang="ts">
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { SettingsState } from "./contracts";
import { useDashboardSettings } from "./useDashboardSettings";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ state: SettingsState; context: OpsPageContext; port: OpsPagePort }>();
const {
  model,
  draft,
  share,
  snapshotVisibility,
  pending,
  review,
  dirty,
  stale,
  writable,
  canSave,
  validation,
  validExpiration,
  notice,
  lastReceipt,
  base,
  missionBase,
  execute,
  page,
  discard,
  rebase,
  navigate,
  exportDashboard,
} = useDashboardSettings(props);
const label = (value: string) => value.replaceAll("_", " ");
const encode = encodeURIComponent;
</script>
<template>
  <section
    id="dashboard-settings-feature"
    class="min-w-0 space-y-5 p-4 lg:p-6"
    :aria-busy="pending"
  >
    <header class="flex flex-wrap items-start justify-between gap-4 border-b border-base-300 pb-5">
      <div class="min-w-0">
        <p class="font-mono text-xs uppercase tracking-widest text-base-content/60">
          Ops / Dashboard settings
        </p>
        <h1 class="mt-2 break-words text-2xl font-semibold">{{ model.name }}</h1>
        <p class="mt-2 text-sm text-base-content/70">
          Saved draft <span class="font-mono">v{{ model.document_version }}</span> · Published
          <span class="font-mono">{{
            model.published_version ? "v" + model.published_version : "—"
          }}</span>
          · {{ model.lifecycle
          }}<span v-if="dirty" id="settings-dirty" class="text-warning"> · Unsaved metadata</span>
        </p>
      </div>
      <nav aria-label="Dashboard settings navigation" class="flex flex-wrap gap-2">
        <a
          id="settings-directory"
          class="btn btn-sm btn-ghost"
          :href="missionBase + '/dashboards'"
          @click="navigate($event, missionBase + '/dashboards')"
          >Dashboards</a
        >
        <a
          id="settings-viewer"
          class="btn btn-sm btn-ghost"
          :href="base"
          @click="navigate($event, base)"
          >View</a
        >
        <a
          v-if="model.lifecycle === 'active'"
          id="settings-editor"
          class="btn btn-sm btn-ghost"
          :href="base + '/edit'"
          @click="navigate($event, base + '/edit')"
          >Edit layout</a
        >
        <button
          id="settings-reload"
          class="btn btn-sm"
          :disabled="pending"
          @click="execute('reload_settings')"
        >
          Reload settings
        </button>
      </nav>
    </header>
    <p id="settings-freshness" class="text-xs text-base-content/55">
      Loaded {{ model.loaded_at }}. Shares and snapshots refer to saved state, not unsaved form
      values.
    </p>
    <p
      v-if="notice || review || pending"
      id="settings-outcome"
      role="status"
      class="break-words border-l-2 border-warning bg-base-200 p-3 text-sm"
    >
      {{
        pending
          ? "Waiting for confirmation…"
          : notice || "Reload settings and review the current state before another change."
      }}
    </p>
    <a
      v-if="
        lastReceipt?.resource_id && ['create_share', 'create_snapshot'].includes(lastReceipt.event)
      "
      id="settings-created-link"
      class="inline-block break-all text-sm text-primary underline"
      :href="
        missionBase +
        (lastReceipt.event === 'create_share' ? '/dashboard-shares/' : '/dashboard-snapshots/') +
        encode(lastReceipt.resource_id)
      "
      @click="
        navigate(
          $event,
          missionBase +
            (lastReceipt.event === 'create_share'
              ? '/dashboard-shares/'
              : '/dashboard-snapshots/') +
            encode(lastReceipt.resource_id),
        )
      "
      >Open created {{ lastReceipt.event === "create_share" ? "share" : "snapshot" }}</a
    >
    <section
      v-if="stale && dirty"
      id="settings-stale"
      class="space-y-3 border border-warning/50 bg-warning/5 p-4"
    >
      <h2 class="font-semibold">The saved revision changed</h2>
      <p class="text-sm">
        Your edits are intact. Review the loaded values before using this revision or discard your
        local edits.
      </p>
      <details id="settings-current" class="text-sm">
        <summary class="cursor-pointer font-medium">
          Loaded metadata · v{{ model.document_version }} / revision {{ model.revision }}
        </summary>
        <dl class="mt-3 space-y-2">
          <div>
            <dt class="text-xs text-base-content/60">Name</dt>
            <dd>{{ model.name }}</dd>
          </div>
          <div>
            <dt class="text-xs text-base-content/60">Description</dt>
            <dd>{{ model.description || "—" }}</dd>
          </div>
          <div>
            <dt class="text-xs text-base-content/60">Tags</dt>
            <dd>{{ model.tags.join(", ") || "—" }}</dd>
          </div>
          <div>
            <dt class="text-xs text-base-content/60">Runtime defaults</dt>
            <dd class="whitespace-pre-wrap break-all font-mono text-xs">
              {{ model.defaults_json }}
            </dd>
          </div>
        </dl>
      </details>
      <button id="settings-rebase" class="btn btn-sm" :disabled="pending || review" @click="rebase">
        Use loaded revision for my edits
      </button>
    </section>
    <div class="grid min-w-0 gap-5 lg:grid-cols-[minmax(0,1.5fr)_minmax(18rem,1fr)]">
      <form
        id="settings-form"
        class="min-w-0 border border-base-300 bg-base-200/20 p-4"
        @submit.prevent="execute('save_settings')"
      >
        <h2 class="text-lg font-semibold">Metadata &amp; runtime defaults</h2>
        <p class="mt-1 text-xs text-base-content/60">
          Saving creates a draft version. It does not publish or change the dashboard layout.
        </p>
        <fieldset class="mt-4 space-y-4" :disabled="pending || model.lifecycle === 'archived'">
          <div>
            <label for="settings-name" class="mb-1 block text-xs font-medium">Name</label
            ><input
              id="settings-name"
              v-model="draft.name"
              class="input w-full"
              required
              maxlength="120"
            />
          </div>
          <div>
            <label for="settings-description" class="mb-1 block text-xs font-medium"
              >Description</label
            ><textarea
              id="settings-description"
              v-model="draft.description"
              class="textarea min-h-20 w-full"
              maxlength="500"
            ></textarea>
          </div>
          <div>
            <label for="settings-tags" class="mb-1 block text-xs font-medium"
              >Tags · comma separated</label
            ><input id="settings-tags" v-model="draft.tags" class="input w-full" />
            <p class="mt-1 text-xs text-base-content/50">Up to 32 unique tags.</p>
          </div>
          <div>
            <label for="settings-defaults" class="mb-1 block text-xs font-medium"
              >Runtime defaults · JSON</label
            ><textarea
              id="settings-defaults"
              v-model="draft.defaults_json"
              class="textarea min-h-56 w-full font-mono text-xs"
              spellcheck="false"
              aria-describedby="settings-defaults-help"
            ></textarea>
            <p id="settings-defaults-help" class="mt-1 text-xs text-base-content/50">
              Complete JSON object, up to 32 KiB. Unchanged context and extension fields are
              preserved.
            </p>
          </div>
          <p v-if="validation" id="settings-validation" role="status" class="text-sm text-warning">
            {{ validation }}
          </p>
          <div class="flex flex-wrap justify-end gap-2">
            <button
              id="settings-discard"
              type="button"
              class="btn btn-sm btn-ghost"
              :disabled="!dirty && !stale"
              @click="discard"
            >
              Discard local edits
            </button>
            <button
              id="settings-save"
              type="submit"
              class="btn btn-sm btn-primary"
              :disabled="!canSave"
            >
              Save draft settings
            </button>
          </div>
        </fieldset>
      </form>
      <aside class="min-w-0 space-y-4">
        <section class="border border-base-300 p-4">
          <h2 class="font-semibold">Access &amp; portability</h2>
          <p class="mt-2 text-sm text-base-content/65">
            Access remains restricted to authorized mission members. Sharing does not bypass mission
            permissions.
          </p>
          <a
            id="settings-export"
            class="btn btn-sm btn-outline mt-4"
            :href="base + '/export'"
            :aria-disabled="!writable"
            @click="exportDashboard"
            >Export latest saved draft</a
          >
          <p class="mt-2 text-xs text-base-content/55">
            Downloads a portable JSON artifact. The server records the export; reload to see its
            deployment record.
          </p>
          <ul id="settings-deployments" class="mt-4 space-y-2">
            <li
              v-for="entry in model.deployments.rows"
              :key="entry.id"
              class="break-words border-t border-base-300 pt-2 text-xs"
            >
              {{ entry.environment }} · v{{ entry.document_version }} · {{ entry.status
              }}<br /><code>{{ entry.digest_prefix }}</code>
            </li>
          </ul>
          <p v-if="!model.deployments.rows.length" class="mt-3 text-xs text-base-content/55">
            No deployment records on this page.
          </p>
          <div class="mt-3 flex gap-2">
            <button
              v-if="model.query.after_deployment"
              id="settings-reset-deployments"
              class="btn btn-xs"
              :disabled="pending"
              @click="page('after_deployment', null)"
            >
              First page
            </button>
            <button
              v-if="model.deployments.next"
              id="settings-more-deployments"
              class="btn btn-xs"
              :disabled="pending"
              @click="page('after_deployment', model.deployments.next)"
            >
              More deployments
            </button>
          </div>
        </section>
        <section class="border border-error/30 bg-error/5 p-4">
          <h2 class="font-semibold">Lifecycle</h2>
          <p class="mt-2 text-sm text-base-content/65">
            Archiving removes the dashboard from active lists. Saved versions and immutable
            snapshots are retained.
          </p>
          <button
            v-if="model.lifecycle === 'active'"
            id="settings-archive"
            class="btn btn-sm btn-ghost mt-3 text-error"
            :disabled="!writable"
            @click="execute('archive_dashboard')"
          >
            Archive dashboard
          </button>
          <p v-else id="settings-archived" class="mt-3 text-sm">
            This dashboard is archived. Authoring is disabled.
          </p>
        </section>
      </aside>
    </div>
    <div class="grid min-w-0 gap-5 xl:grid-cols-2">
      <section id="settings-sharing" class="min-w-0 border border-base-300 p-4">
        <h2 class="text-lg font-semibold">Mission shares</h2>
        <p class="mt-1 text-xs text-base-content/60">
          Authenticated links to this saved dashboard. Unsaved metadata and runtime selections are
          not included.
        </p>
        <form
          id="share-form"
          class="mt-4 grid gap-3 sm:grid-cols-2"
          @submit.prevent="execute('create_share')"
        >
          <div>
            <label for="share-visibility" class="mb-1 block text-xs font-medium"
              >Data visibility</label
            ><select
              id="share-visibility"
              v-model="share.data_visibility"
              class="select w-full"
              :disabled="pending"
            >
              <option value="authorized_runtime_data">Authorized runtime data</option>
              <option value="definition_only">Definition only</option>
            </select>
          </div>
          <div>
            <label for="share-expiration" class="mb-1 block text-xs font-medium"
              >Expires in hours · blank means never</label
            ><input
              id="share-expiration"
              v-model="share.expires_in_hours"
              type="number"
              min="1"
              max="8760"
              class="input w-full"
              :disabled="pending"
            />
          </div>
          <p v-if="!validExpiration" class="text-sm text-warning sm:col-span-2">
            Use a whole number from 1 to 8760, or leave blank.
          </p>
          <button
            id="share-create"
            class="btn btn-sm btn-primary sm:col-span-2"
            :disabled="!writable || !validExpiration"
          >
            Create mission share
          </button>
        </form>
        <ul id="settings-shares" class="mt-4 space-y-2">
          <li
            v-for="entry in model.shares.rows"
            :key="entry.id"
            :data-share-id="entry.id"
            class="flex items-start gap-3 border-t border-base-300 pt-3 text-xs"
          >
            <div class="min-w-0 flex-1">
              <a
                class="break-all font-mono text-primary hover:underline"
                :href="missionBase + '/dashboard-shares/' + encode(entry.id)"
                @click="navigate($event, missionBase + '/dashboard-shares/' + encode(entry.id))"
                >{{ entry.id }}</a
              >
              <p class="mt-1">{{ label(entry.data_visibility) }} · {{ entry.state }}</p>
              <p class="mt-1 text-base-content/55">
                {{ entry.expires_at ? "Expires " + entry.expires_at : "No expiration" }}
              </p>
            </div>
            <button
              v-if="entry.state !== 'revoked'"
              :data-revoke-share="entry.id"
              class="btn btn-xs btn-ghost"
              :disabled="!writable"
              @click="execute('revoke_share', entry.id)"
            >
              Revoke
            </button>
          </li>
        </ul>
        <p v-if="!model.shares.rows.length" class="mt-4 text-sm text-base-content/55">
          No shares on this page.
        </p>
        <div class="mt-4 flex gap-2">
          <button
            v-if="model.query.after_share"
            id="settings-reset-shares"
            class="btn btn-xs"
            :disabled="pending"
            @click="page('after_share', null)"
          >
            First page</button
          ><button
            v-if="model.shares.next"
            id="settings-more-shares"
            class="btn btn-xs"
            :disabled="pending"
            @click="page('after_share', model.shares.next)"
          >
            More shares
          </button>
        </div>
      </section>
      <section id="settings-snapshots" class="min-w-0 border border-base-300 p-4">
        <h2 class="text-lg font-semibold">Definition snapshots</h2>
        <p class="mt-1 text-xs text-base-content/60">
          Capture the saved draft at an exact version. These preserve definitions, not frozen
          telemetry values or unsaved edits.
        </p>
        <form
          id="snapshot-form"
          class="mt-4 space-y-3"
          @submit.prevent="execute('create_snapshot')"
        >
          <div>
            <label for="snapshot-visibility" class="mb-1 block text-xs font-medium"
              >Data visibility</label
            ><select
              id="snapshot-visibility"
              v-model="snapshotVisibility"
              class="select w-full"
              :disabled="pending"
            >
              <option value="definition_only">Definition only</option>
              <option value="authorized_runtime_data">Authorized runtime data</option>
            </select>
          </div>
          <button id="snapshot-create" class="btn btn-sm btn-primary w-full" :disabled="!writable">
            Capture saved draft v{{ model.document_version }}
          </button>
        </form>
        <ul id="settings-snapshot-list" class="mt-4 space-y-3">
          <li
            v-for="entry in model.snapshots.rows"
            :key="entry.id"
            class="border-t border-base-300 pt-3 text-xs"
          >
            <a
              class="break-all font-mono text-primary hover:underline"
              :href="missionBase + '/dashboard-snapshots/' + encode(entry.id)"
              @click="navigate($event, missionBase + '/dashboard-snapshots/' + encode(entry.id))"
              >{{ entry.id }}</a
            >
            <p class="mt-1">v{{ entry.document_version }} · {{ label(entry.data_visibility) }}</p>
            <p class="mt-1 text-base-content/55">
              {{ label(entry.data_semantics) }} · {{ entry.created_at }}
            </p>
          </li>
        </ul>
        <p v-if="!model.snapshots.rows.length" class="mt-4 text-sm text-base-content/55">
          No snapshots on this page.
        </p>
        <div class="mt-4 flex gap-2">
          <button
            v-if="model.query.after_snapshot"
            id="settings-reset-snapshots"
            class="btn btn-xs"
            :disabled="pending"
            @click="page('after_snapshot', null)"
          >
            First page</button
          ><button
            v-if="model.snapshots.next"
            id="settings-more-snapshots"
            class="btn btn-xs"
            :disabled="pending"
            @click="page('after_snapshot', model.snapshots.next)"
          >
            More snapshots
          </button>
        </div>
      </section>
    </div>
  </section>
</template>
