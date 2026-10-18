import { computed, provide, shallowRef, type ComputedRef } from "vue";
import { pageHeaderKey, type PageHeaderHost } from "@cadence/plugin-sdk/page-header";
import { readPageHeader, type AdmittedHeader } from "@cadence/plugin-sdk/page-header-validation";
import {
  isRouteId,
  routeCatalog,
  type Layer,
  type RouteHeaderPolicy,
} from "@cadence/plugin-sdk/routes";

/**
 * The host side of `useOpsHeader` and `useManagementHeader`: one page owns the header at a time, it must
 * claim the route actually mounted, and what it sends is admitted before it is
 * drawn. A rejected header falls back to the route's own title and description.
 */
export function providePageHeaderHost(route: () => string) {
  const owner = shallowRef<symbol>();
  const header = shallowRef<AdmittedHeader | null>(null);
  const policy: ComputedRef<(RouteHeaderPolicy & { layer: Layer }) | null> = computed(() => {
    const id = route();
    return isRouteId(id) ? { ...routeCatalog[id].header, layer: routeCatalog[id].layer } : null;
  });

  const host: PageHeaderHost = {
    route,
    claim(next, routes) {
      if (owner.value && owner.value !== next)
        console.error("Two components claimed the page header; only the routed page may.");
      owner.value = next;
      header.value = null;
      if (!routes.includes(route()))
        console.error(`The page header describes ${routes.join(", ")} but ${route()} is mounted.`);
    },
    update(from, value) {
      const current = policy.value;
      const kind = current?.kind;
      if (from !== owner.value || !current || (kind !== "collection" && kind !== "resource"))
        return;
      try {
        header.value = readPageHeader(value, { kind, layer: current.layer });
      } catch (error) {
        header.value = null;
        console.error(error);
      }
    },
    release(from) {
      if (from !== owner.value) return;
      owner.value = undefined;
      header.value = null;
    },
  };
  provide(pageHeaderKey, host);
  return { claimed: computed(() => owner.value !== undefined), header, policy };
}
