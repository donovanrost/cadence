import { catalogHref, element, label } from "../../shared/test-support";
export function artifactFixture() {
  return {
    presentation: {
      root: element(),
      child_wrapper: element(),
      header: {
        attrs: {},
        body: element(),
        content: element(),
        title: label("mission.yaml"),
        breadcrumbs: { attrs: {}, items: [] },
      },
      artifact_show: {
        artifact: {
          format_key: "cadence_yaml",
          media_type: "application/yaml",
          content_sha256: "abc",
          uploaded_at: "2026-09-06",
          download_href: `${catalogHref}/artifacts/one/download`,
        },
        runs: [],
      },
    },
  };
}
