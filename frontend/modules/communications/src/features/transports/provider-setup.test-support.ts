import { required } from "../../../../../test-support/required";
import { transportFormPayload } from "./fixtures.test-support";
import type { FormInput } from "../../shared/form-workflow.contracts";

export function providerTransportForm() {
  const props = transportFormPayload();
  props.form.fields.display_name.label = "Display name";
  props.form.fields.origin.label = "Origin";
  props.form.fields.origin.options = [
    { label: "Direct", value: "direct", disabled: false },
    { label: "Ground station provider", value: "provider_managed", disabled: false },
  ];
  props.form.fields.transport_kind.options = [
    { label: "TCP socket", value: "tcp_socket", disabled: false },
  ];
  props.form.fields.mission_provider_id.label = "Ground network provider";
  props.form.fields.mission_provider_id.placeholder = "Select a provider";
  props.form.fields.mission_provider_id.options = [
    { label: "Simulator · v2", value: "provider-1", disabled: false },
    { label: "Backup · v4", value: "provider-2", disabled: false },
  ];
  props.form.fields.service_profile_id.label = "Service profile";
  props.form.fields.service_profile_id.placeholder = "Select service";
  props.form.fields.delivery_profile_id.label = "Delivery profile";
  props.form.fields.delivery_profile_id.placeholder = "Select delivery";
  props.form.provider.versions = [
    { id: "provider-1", version: 2 },
    { id: "provider-2", version: 4 },
  ];
  props.form.provider.ready_count = 2;
  props.form.provider.empty_state.visible = false;
  props.form.provider_derived.title = "Provider-derived runtime";
  props.form.provider_derived.description =
    "Endpoint, framing and reliability are provider-owned and read-only.";
  props.form.provider_derived.configuration.empty_text =
    "Select compatible profiles to preview the configuration.";
  return props;
}

export function providerValidation(input: FormInput) {
  const draft = required(input.transport);
  const selected = !!draft.mission_provider_id;
  const prefix = draft.mission_provider_id;
  const configured = !!draft.service_profile_id && !!draft.delivery_profile_id;
  const endpoint = configured ? "127.0.0.1:5100" : null;
  return {
    valid: configured && !!draft.display_name?.trim(),
    transport_review: { origin: "provider_managed", endpoint },
    provider_setup: {
      version: 1,
      transport_kind: draft.transport_kind,
      provider_id: draft.mission_provider_id,
      provider_version: draft.mission_provider_version,
      service_profile_id: draft.service_profile_id,
      delivery_profile_id: draft.delivery_profile_id,
      provider_name: selected ? (prefix === "provider-1" ? "Simulator" : "Backup") : null,
      services: selected
        ? [{ label: "Realtime telemetry · v3", value: prefix + "-service-v3", disabled: false }]
        : [],
      deliveries: draft.service_profile_id
        ? [{ label: "Primary ingress · v7", value: prefix + "-delivery-v7", disabled: false }]
        : [],
      configuration: configured
        ? [
            ["Endpoint", required(endpoint)],
            ["Mode", "listen"],
            ["Direction", "inbound"],
            ["Framing", "fixed_size"],
            ["Frame bytes", "1115"],
            ["Reconnect", "never"],
            ["TLS", "Disabled"],
          ].map(([label, value]) => ({ label, value, mono: true }))
        : [],
    },
  };
}
