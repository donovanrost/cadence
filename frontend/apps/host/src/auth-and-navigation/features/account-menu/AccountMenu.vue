<script setup lang="ts">
import NotificationBell from "../notifications/NotificationBell.vue";
import { computed } from "vue";
import { readAccountContext } from "./contracts";
import AccountDropdownMenu from "@cadence/ui/AccountDropdownMenu.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import { navigateAttrs } from "../../shared/navigation";
const props = defineProps<{ context: unknown; id: string }>();
const model = computed(() => readAccountContext(props.context));
const otherOrganizations = computed(() => {
  const current = model.value;
  if (!current?.organization) return [];
  const currentId = current.organization.organization_id;
  return current.organizations.filter((organization) => organization.organization_id !== currentId);
});
</script>
<template>
  <div v-if="model?.user" class="flex items-center gap-2">
    <NotificationBell :context="props.context" :id="`${id}-notifications`" />
    <AccountDropdownMenu class="dropdown dropdown-end">
      <template #trigger="{ open }"
        ><button
          :id="`${id}-user`"
          type="button"
          :aria-expanded="open"
          class="btn btn-ghost btn-sm gap-1"
        >
          <span class="max-w-24 truncate text-xs text-base-content/60 sm:max-w-48">{{
            model.user.display_name || model.user.email
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
              {{ model.user.display_name || model.user.email }}
            </p>
            <p v-if="model.user.display_name" class="text-xs text-base-content/60 truncate">
              {{ model.user.email }}
            </p>
          </div>
          <div v-if="model.organization" class="border-t border-primary/10 mt-1 pt-1">
            <p class="hud-label px-3 py-1">Organization</p>
            <p class="px-3 py-2 text-sm truncate">{{ model.organization.display_name }}</p>
            <!-- Native submit items keep their form mounted until document navigation.
                 Prevent only Reka's select dismissal, never the click or submit event. -->
            <form
              v-for="organization in otherOrganizations"
              :id="`${id}-switch-${organization.organization_id}`"
              :key="organization.organization_id"
              action="/session/organization"
              method="post"
            >
              <input type="hidden" name="_method" value="put" /><input
                type="hidden"
                name="_csrf_token"
                :value="model.csrf_token"
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
          <CadenceMenuItem v-if="model.platform_admin" :active="open" @select="onItemSelect"
            ><a
              v-bind="model.admin_mode ? navigateAttrs('/admin') : { href: '/admin-mode' }"
              class="flex items-center gap-2 px-3 py-2 text-xs uppercase text-base-content/70 hover:text-primary"
              ><span class="hero-cog-6-tooth h-4 w-4"></span
              >{{ model.admin_mode ? "System administration" : "Enter admin mode" }}</a
            ></CadenceMenuItem
          >
          <form
            v-if="model.admin_mode"
            :id="`${id}-leave-admin`"
            action="/admin-mode"
            method="post"
          >
            <input type="hidden" name="_method" value="delete" /><input
              type="hidden"
              name="_csrf_token"
              :value="model.csrf_token"
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
              :value="model.csrf_token"
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
  <p v-else-if="!model" :id="`${id}-unavailable`" role="status" class="text-xs">
    Account menu unavailable
  </p>
</template>
