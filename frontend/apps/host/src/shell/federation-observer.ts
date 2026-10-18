/** Vue can update a placement in place, without adding or removing any nodes. */
export function observeFederationRoots(target: Node, refresh: () => void): MutationObserver {
  const observer = new MutationObserver(refresh);
  observer.observe(target, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: [
      "data-application-key",
      "data-surface-id",
      "data-host-scope",
      "data-organization-id",
      "data-user-id",
      "data-mission-id",
      "data-spacecraft-id",
      "data-query-params",
      "data-catalog-url",
      "data-fallback-href",
    ],
  });
  return observer;
}
