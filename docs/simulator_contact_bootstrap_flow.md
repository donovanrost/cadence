# Simulator Contact Bootstrap Flow

This flow bootstraps a mission so `cadence_simulator` can resolve its socket
and framing settings from a realized Cadence contact instead of manually
providing `--tcp` and `--tc-frame-size`.

The examples assume:

- Cadence API is available at `http://127.0.0.1:4001`
- you either have an authenticated bearer token in `$API_TOKEN`, or Cadence has
  not been bootstrapped yet
- organization is `org-alpha`
- mission is `mission-alpha`

For a scripted bootstrap, use:

```bash
cd apps/cadence_simulator
mix escript.build
./cadence_simulator bootstrap_contact
```

The simulator bootstrap command reads environment variables such as:

- `CADENCE_BASE_URL`
- `CADENCE_API_TOKEN`
- `CADENCE_ORGANIZATION_ID`
- `CADENCE_MISSION_ID`
- `CADENCE_DEFINITIONS_PATH`

If you prefer the wrapper script, run it without starting local applications:

```bash
mix run --no-start scripts/bootstrap_simulator_contact.exs
```

## 1. Create reusable provider and transport config

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  -H "content-type: application/json" \
  -X POST \
  http://127.0.0.1:4001/api/organizations/org-alpha/missions/mission-alpha/provider_profiles \
  -d '{
    "provider_profile": {
      "provider_profile_id": "tcp-downlink-profile",
      "adapter_key": "tcp_socket",
      "configuration": {
        "mode": "listen",
        "port": 0,
        "ingress_protocol_family": "tm",
        "frame_size": 1115,
        "ingress_metadata": {
          "frame_size": 1115,
          "ocf_length": 0
        }
      }
    }
  }'
```

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  -H "content-type: application/json" \
  -X POST \
  http://127.0.0.1:4001/api/organizations/org-alpha/missions/mission-alpha/transport_profiles \
  -d '{
    "transport_profile": {
      "transport_profile_id": "uplink-gateway-profile",
      "family_key": "uplink_gateway",
      "target_scope": "path",
      "configuration": {
        "transport_profile": "tc"
      }
    }
  }'
```

## 2. Create reusable path templates

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  -H "content-type: application/json" \
  -X POST \
  http://127.0.0.1:4001/api/organizations/org-alpha/missions/mission-alpha/path_templates \
  -d '{
    "path_template": {
      "path_template_id": "uplink-template-alpha",
      "path_id": "uplink-path-alpha",
      "direction": "uplink",
      "selection_role": "selected",
      "source_endpoint_ref": "source-endpoint-001",
      "transport_profile_ids": ["uplink-gateway-profile"]
    }
  }'
```

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  -H "content-type: application/json" \
  -X POST \
  http://127.0.0.1:4001/api/organizations/org-alpha/missions/mission-alpha/path_templates \
  -d '{
    "path_template": {
      "path_template_id": "downlink-template-alpha",
      "path_id": "downlink-path-alpha",
      "direction": "downlink",
      "selection_role": "selected",
      "source_endpoint_ref": "source-endpoint-001",
      "provider_profile_ids": ["tcp-downlink-profile"]
    }
  }'
```

## 3. Schedule and realize a contact from templates

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  -H "content-type: application/json" \
  -X POST \
  http://127.0.0.1:4001/api/organizations/org-alpha/missions/mission-alpha/scheduled_contacts \
  -d '{
    "scheduled_contact": {
      "scheduled_contact_id": "contact-alpha",
      "source_endpoint_refs": ["source-endpoint-001"],
      "path_template_ids": ["uplink-template-alpha", "downlink-template-alpha"],
      "starts_at": "2026-03-30T18:00:00Z",
      "ends_at": "2026-03-30T18:10:00Z"
    }
  }'
```

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  -H "content-type: application/json" \
  -X POST \
  http://127.0.0.1:4001/api/organizations/org-alpha/missions/mission-alpha/scheduled_contacts/contact-alpha/realize \
  -d '{
    "realization": {
      "clock_mode": "live"
    }
  }'
```

## 4. Run the simulator against the realized contact

Telemetry mode:

```bash
cadence_simulator telemetry \
  --definitions legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml \
  --cadence-url http://127.0.0.1:4001 \
  --api-token "$API_TOKEN" \
  --organization-id org-alpha \
  --mission-id mission-alpha \
  --realized-contact-id contact-alpha_run \
  --path-id downlink-path-alpha
```

COP-1 loopback mode:

```bash
cadence_simulator cop1_loopback \
  --cadence-url http://127.0.0.1:4001 \
  --api-token "$API_TOKEN" \
  --organization-id org-alpha \
  --mission-id mission-alpha \
  --realized-contact-id contact-alpha_run \
  --path-id uplink-path-alpha \
  --transport-binding-id uplink-gateway-profile
```

## 5. Inspect the live runtime if needed

Realized contact snapshot:

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  http://127.0.0.1:4001/api/organizations/org-alpha/missions/mission-alpha/realized_contacts/contact-alpha_run/runtime
```

Path runtime snapshot:

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  http://127.0.0.1:4001/api/organizations/org-alpha/missions/mission-alpha/realized_contacts/contact-alpha_run/paths/downlink-path-alpha/runtime
```
