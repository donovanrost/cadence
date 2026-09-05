<script setup lang="ts">
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue";
import CadencePageTitle from "./ui/components/CadencePageTitle.vue";
import CadenceCard from "./ui/components/CadenceCard.vue";

type Navigation = {
  organizations_href: string;
  runtime_href: string;
  create_organization_href: string;
};

type Presentation = {
  title: string;
  subtitle: string;
  organizations: {
    title: string;
    action_label: string;
  };
  users: {
    title: string;
    action_label: string;
    coming_soon: string;
  };
  runtime: {
    title: string;
    description: string;
    action_label: string;
  };
  quick_actions: {
    title: string;
    create_organization_title: string;
    create_organization_description: string;
  };
};

defineProps<{
  organization_count: number;
  user_count: number;
  presentation: Presentation;
  navigation: Navigation;
}>();
</script>

<template>
  <div id="admin-home" class="space-y-8">
    <CadencePageHeaderFrame variant="compact">
      <div>
        <div>
          <CadencePageTitle>
            {{ presentation.title }}
          </CadencePageTitle>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">
            {{ presentation.subtitle }}
          </p>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
      <CadenceCard
        id="admin-home-organizations-card"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <p class="hud-label">{{ presentation.organizations.title }}</p>
        <p class="mt-2 font-mono text-3xl font-bold">{{ organization_count }}</p>
        <a
          id="admin-home-organizations-link"
          :href="navigation.organizations_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm mt-4 w-full"
          >{{ presentation.organizations.action_label }}</a
        >
      </CadenceCard>

      <CadenceCard
        id="admin-home-users-card"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <p class="hud-label">{{ presentation.users.title }}</p>
        <p class="mt-2 font-mono text-3xl font-bold">{{ user_count }}</p>
        <button
          id="admin-home-users-button"
          type="button"
          class="btn btn-secondary btn-sm mt-4 w-full"
          disabled
        >
          {{ presentation.users.action_label }}
          <span class="text-xs">{{ presentation.users.coming_soon }}</span>
        </button>
      </CadenceCard>

      <CadenceCard
        id="admin-home-runtime-card"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <p class="hud-label">{{ presentation.runtime.title }}</p>
        <p class="mt-2 text-sm text-base-content/70">
          {{ presentation.runtime.description }}
        </p>
        <a
          id="admin-home-runtime-link"
          :href="navigation.runtime_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm mt-4 w-full"
          >{{ presentation.runtime.action_label }}</a
        >
      </CadenceCard>
    </div>

    <section aria-labelledby="admin-home-quick-actions-title">
      <h2 id="admin-home-quick-actions-title" class="text-lg font-bold mb-4">
        {{ presentation.quick_actions.title }}
      </h2>
      <a
        id="admin-home-create-organization-link"
        :href="navigation.create_organization_href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="block"
      >
        <CadenceCard
          class="card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]"
          body-class="card-body p-6"
        >
          <div class="flex items-center gap-4">
            <div>
              <h3 class="font-semibold">
                {{ presentation.quick_actions.create_organization_title }}
              </h3>
              <p class="text-sm text-base-content/60">
                {{ presentation.quick_actions.create_organization_description }}
              </p>
            </div>
          </div>
        </CadenceCard>
      </a>
    </section>
  </div>
</template>
