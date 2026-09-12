import { presentationBreadcrumbs } from "@cadence/ui/page-chrome";
import type { Header } from "./contracts";

export function installationBreadcrumbs(breadcrumbs: Header["breadcrumbs"]) {
  return breadcrumbs.items.flatMap((item) =>
    "label" in item
      ? [{ label: item.label, ...(item.href ? { href: item.href } : {}) }]
      : presentationBreadcrumbs({ items: [item] }),
  );
}
