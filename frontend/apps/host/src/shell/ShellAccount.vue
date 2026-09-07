<script setup>
import AccountDropdownMenu from "@cadence/ui/AccountDropdownMenu.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import { navigateAttrs } from "./shell-navigation";
defineProps({ context: { type: Object, required: true }, id: { type: String, required: true } });
</script>
<template>
  <div v-if="context.user" class="flex items-center gap-2">
    <AccountDropdownMenu class="dropdown dropdown-end">
      <template #trigger="{ open }"
        ><button
          :id="`${id}-notifications`"
          type="button"
          aria-label="Notifications"
          :aria-expanded="open"
          class="btn btn-ghost btn-sm btn-circle relative"
        >
          <span class="hero-bell h-5 w-5"></span
          ><span
            v-if="context.unread_count"
            class="badge badge-primary badge-xs absolute -top-0.5 -right-0.5 font-mono"
            >{{ context.unread_count > 9 ? "9+" : context.unread_count }}</span
          >
        </button></template
      >
      <template #content="{ open, onItemSelect }"
        ><div
          role="menu"
          class="dropdown-content menu bg-base-200 z-[var(--z-popover)] w-80 p-2 shadow-lg border border-primary/20 max-h-96 overflow-y-auto"
        >
          <p class="hud-label px-3 py-2">
            Notifications
            <span v-if="context.unread_count" class="text-primary"
              >({{ context.unread_count }} unread)</span
            >
          </p>
          <p
            v-if="!context.notifications.length"
            class="px-3 py-4 text-center text-sm text-base-content/60"
          >
            No notifications
          </p>
          <CadenceMenuItem
            v-for="notification in context.notifications"
            :key="notification.notification_id"
            :active="open"
            @select="onItemSelect"
            ><a v-bind="navigateAttrs('/notifications')" class="flex items-start gap-2 px-3 py-2"
              ><span
                v-if="!notification.read_at"
                class="mt-1.5 w-1.5 h-1.5 rounded-full bg-primary shrink-0"
              ></span
              ><span class="min-w-0"
                ><span class="block text-xs font-semibold truncate">{{ notification.title }}</span
                ><span
                  v-if="notification.body"
                  class="block text-xs text-base-content/70 truncate"
                  >{{ notification.body }}</span
                ></span
              ></a
            ></CadenceMenuItem
          >
          <CadenceMenuItem :active="open" @select="onItemSelect"
            ><a
              v-bind="navigateAttrs('/notifications')"
              class="border-t border-primary/10 mt-1 pt-2 text-xs text-primary uppercase tracking-wide"
              >See all notifications</a
            ></CadenceMenuItem
          >
        </div></template
      >
    </AccountDropdownMenu>
    <AccountDropdownMenu class="dropdown dropdown-end">
      <template #trigger="{ open }"
        ><button
          :id="`${id}-user`"
          type="button"
          :aria-expanded="open"
          class="btn btn-ghost btn-sm gap-1"
        >
          <span class="text-xs text-base-content/60">{{
            context.user.display_name || context.user.email
          }}</span
          ><span class="hero-chevron-down h-3 w-3 opacity-60"></span></button
      ></template>
      <template #content="{ open, onItemSelect }"
        ><div
          role="menu"
          class="dropdown-content menu bg-base-200 z-[var(--z-popover)] w-72 p-2 shadow-lg border border-primary/20"
        >
          <div class="px-3 py-2">
            <p class="text-sm font-semibold">
              {{ context.user.display_name || context.user.email }}
            </p>
            <p v-if="context.user.display_name" class="text-xs text-base-content/60 truncate">
              {{ context.user.email }}
            </p>
          </div>
          <div v-if="context.organization" class="border-t border-primary/10 mt-1 pt-1">
            <p class="hud-label px-3 py-1">Organization</p>
            <p class="px-3 py-2 text-sm truncate">{{ context.organization.display_name }}</p>
            <!-- Native submit items keep their form mounted until document navigation.
                 Prevent only Reka's select dismissal, never the click or submit event. -->
            <form
              v-for="organization in context.organizations.filter(
                (org) => org.organization_id !== context.organization.organization_id,
              )"
              :id="`${id}-switch-${organization.organization_id}`"
              :key="organization.organization_id"
              action="/session/organization"
              method="post"
            >
              <input type="hidden" name="_method" value="put" /><input
                type="hidden"
                name="_csrf_token"
                :value="context.csrf_token"
              /><input type="hidden" name="organization_id" :value="organization.organization_id" />
              <CadenceMenuItem :active="open" @select.prevent
                ><button
                  type="submit"
                  class="flex w-full items-center gap-2 px-3 py-2 text-xs text-base-content/70 hover:text-primary"
                >
                  {{ organization.display_name }}
                </button></CadenceMenuItem
              >
            </form>
          </div>
          <CadenceMenuItem v-if="context.platform_admin" :active="open" @select="onItemSelect"
            ><a
              v-bind="context.admin_mode ? navigateAttrs('/admin') : { href: '/admin-mode' }"
              class="flex items-center gap-2 px-3 py-2 text-xs uppercase text-base-content/70 hover:text-primary"
              ><span class="hero-cog-6-tooth h-4 w-4"></span
              >{{ context.admin_mode ? "System administration" : "Enter admin mode" }}</a
            ></CadenceMenuItem
          >
          <form
            v-if="context.admin_mode"
            :id="`${id}-leave-admin`"
            action="/admin-mode"
            method="post"
          >
            <input type="hidden" name="_method" value="delete" /><input
              type="hidden"
              name="_csrf_token"
              :value="context.csrf_token"
            /><CadenceMenuItem :active="open" @select.prevent
              ><button
                type="submit"
                class="flex w-full gap-2 px-3 py-2 text-xs uppercase text-base-content/70 hover:text-primary"
              >
                <span class="hero-lock-closed h-4 w-4"></span>Leave admin mode
              </button></CadenceMenuItem
            >
          </form>
          <form
            :id="`${id}-sign-out`"
            action="/session"
            method="post"
            class="border-t border-primary/10 mt-1 pt-1"
          >
            <input type="hidden" name="_method" value="delete" /><input
              type="hidden"
              name="_csrf_token"
              :value="context.csrf_token"
            /><CadenceMenuItem :active="open" @select.prevent
              ><button
                type="submit"
                class="flex w-full items-center gap-2 px-3 py-2 text-xs uppercase text-base-content/70 hover:text-primary"
              >
                <span class="hero-arrow-right-start-on-rectangle h-4 w-4"></span>Sign out
              </button></CadenceMenuItem
            >
          </form>
        </div></template
      >
    </AccountDropdownMenu>
  </div>
</template>
