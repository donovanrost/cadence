import { assertShape, attrs, href, list, nullable, shape, text } from "../../shared/validation.ts";
const element = shape({ attrs });
const label = shape({ attrs, text });
const directory = shape({
  presentation: shape({
    root: element,
    header: shape({
      attrs,
      body: element,
      content: element,
      title: label,
      subtitle: label,
      actions: shape({ attrs, new_profile: shape({ id: text, label: text, href }) }),
    }),
    empty_state: nullable(shape({ title: text, description: text })),
    card: nullable(
      shape({
        attrs,
        body: element,
        list_component: element,
        rows: list(
          shape({
            id: text,
            display_name: text,
            version: text,
            downlink_protocol: text,
            uplink_protocol: text,
            applications: text,
            href,
          }),
        ),
      }),
    ),
  }),
});
const detail = shape({
  profile: shape({
    id: text,
    profile_id: text,
    display_name: text,
    version: text,
    lifecycle: text,
    downlink_protocol: text,
    uplink_protocol: text,
    packet_protocol: text,
    frame_parameters: list(shape({ id: text, label: text, value: text })),
    applications: list(shape({ id: text, label: text })),
  }),
  navigation: shape({ breadcrumbs: list(shape({ label: text, href: nullable(href) })) }),
  labels: shape({
    byte_interpretation: text,
    applications: text,
    version_history: text,
    frame_parameters: text,
    no_applications: text,
    downlink_protocol: text,
    uplink_protocol: text,
    packet_protocol: text,
    lifecycle: text,
    version: text,
    downlink: text,
    uplink: text,
  }),
  versions: list(
    shape({
      id: text,
      version: text,
      lifecycle: text,
      downlink_protocol: text,
      uplink_protocol: text,
    }),
  ),
});
export function assertProfileDirectory(value: unknown): void {
  assertShape(directory, value);
}
export function assertProfileDetail(value: unknown): void {
  assertShape(detail, value);
}
