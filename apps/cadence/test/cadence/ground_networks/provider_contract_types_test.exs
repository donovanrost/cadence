defmodule Cadence.GroundNetworks.ProviderContractTypesTest do
  use ExUnit.Case, async: true

  alias Cadence.Contacts.ProviderProfile

  alias Cadence.GroundNetworks.{
    DeliveryProfile,
    Opportunity,
    ProviderCapabilities,
    ProviderContact,
    ProviderContext,
    ProviderError,
    ServiceProfile,
    Validation
  }

  test "ProviderContext keeps credentials behind an opaque reference" do
    profile =
      ProviderProfile.new(%{
        provider_profile_id: "provider-alpha",
        mission_id: "mission-alpha",
        adapter_key: :tcp_socket,
        configuration: %{
          "scheduling" => %{
            "client" => "simulator_http",
            "base_url" => "http://simulator.test",
            "environment_ref" => "environment-alpha",
            "api_token" => "provider-secret"
          }
        }
      })

    assert {:ok,
            %ProviderContext{
              provider_ref: "provider-alpha",
              environment_ref: "environment-alpha",
              credential_ref: credential_ref
            } = context} = ProviderContext.from_provider_profile(profile)

    assert credential_ref == "legacy-provider-profile:provider-alpha:1"
    refute inspect(context) =~ "provider-secret"

    opts = ProviderContext.with_legacy_credential(profile, context, [])
    assert {:ok, "provider-secret"} = opts[:credential_resolver].(credential_ref)
  end

  test "capability and profile documents normalize into provider-neutral values" do
    assert {:ok,
            %ProviderCapabilities{
              reservation: %{idempotency: :native, recovery: :client_reference},
              operations: %{contact_reservation: true}
            }} = ProviderCapabilities.from_external(capabilities_document())

    assert {:ok,
            %ServiceProfile{
              id: "service-realtime-ttc-downlink",
              direction: :downlink,
              state: :active
            }} = ServiceProfile.from_external(service_profile_document())

    assert {:ok,
            %DeliveryProfile{
              id: "delivery-cadence-primary",
              direction: :downlink,
              state: :ready
            }} = DeliveryProfile.from_external(delivery_profile_document())
  end

  test "opportunities validate identity, time, and lifecycle at the adapter boundary" do
    assert {:ok,
            %Opportunity{
              id: "opportunity-123",
              spacecraft_ref: "SC-001",
              availability: :available
            }} = Opportunity.from_external(opportunity_document())

    assert {:error, {:malformed_provider_response, "availability"}} =
             opportunity_document()
             |> Map.put("availability", "invented")
             |> Opportunity.from_external()

    assert {:error, {:malformed_provider_response, "ends_at"}} =
             opportunity_document()
             |> Map.put("ends_at", "2026-07-13T12:00:00Z")
             |> Opportunity.from_external()
  end

  test "contacts retain independent contact, pass, and delivery state" do
    assert {:ok,
            %ProviderContact{
              status: :confirmed,
              pass_phase: :prepass,
              delivery: %{status: :ready, direction: :downlink}
            } = contact} = ProviderContact.from_external(contact_document())

    result = ProviderContact.to_reservation_result(contact)
    assert result["status"] == "confirmed"
    assert result["pass_phase"] == "prepass"
    assert result["delivery_state"] == "ready"

    assert {:error, {:malformed_provider_response, "pass_phase"}} =
             contact_document()
             |> Map.put("pass_phase", "invented")
             |> ProviderContact.from_external()

    assert {:error, {:malformed_provider_response, "status"}} =
             contact_document()
             |> put_in(["delivery", "status"], "invented")
             |> ProviderContact.from_external()
  end

  test "external evidence is string-keyed and recursively redacts credentials" do
    sanitized =
      Validation.sanitize(%{
        api_token: "secret",
        nested: [%{password: "secret", credential_ref: "env://PROVIDER_TOKEN"}]
      })

    assert sanitized == %{
             "api_token" => "[REDACTED]",
             "nested" => [
               %{
                 "password" => "[REDACTED]",
                 "credential_ref" => "env://PROVIDER_TOKEN"
               }
             ]
           }

    error =
      ProviderError.from_response(429, %{
        "error" => %{"code" => "rate_limited", "retryable" => true},
        "authorization" => "Bearer secret"
      })

    assert error.category == :rate_limited
    assert error.retryable
    assert error.evidence["authorization"] == "[REDACTED]"
  end

  defp capabilities_document do
    %{
      "contract_version" => "1.0",
      "provider" => %{"type" => "simulator", "display_name" => "Simulator"},
      "operations" => %{
        "opportunity_search" => true,
        "contact_reservation" => true,
        "contact_modification" => false,
        "contact_cancellation" => true,
        "inventory_discovery" => true,
        "delivery_profile_provisioning" => true
      },
      "reservation" => %{
        "confirmation" => "asynchronous",
        "idempotency" => "native",
        "recovery" => "client_reference"
      },
      "events" => %{
        "polling" => true,
        "webhooks" => false,
        "delivery_semantics" => "at_least_once"
      },
      "search" => %{
        "spacecraft_batch_limit" => 100,
        "station_batch_limit" => 30,
        "page_size_limit" => 100
      },
      "delivery" => %{
        "kinds" => ["realtime_stream"],
        "protocols" => ["tcp"],
        "directions" => ["downlink"]
      }
    }
  end

  defp service_profile_document do
    %{
      "id" => "service-realtime-ttc-downlink",
      "version" => 1,
      "display_name" => "Realtime TT&C downlink",
      "service_kind" => "realtime_telemetry",
      "direction" => "downlink",
      "supported_delivery_kinds" => ["realtime_stream"],
      "data_families" => ["ccsds_tm"],
      "minimum_duration_seconds" => 30,
      "state" => "active",
      "extensions" => %{}
    }
  end

  defp delivery_profile_document do
    %{
      "id" => "delivery-cadence-primary",
      "version" => 1,
      "display_name" => "Cadence primary telemetry ingress",
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "supported_service_profile_refs" => ["service-realtime-ttc-downlink"],
      "state" => "ready",
      "operator_summary" => "Streaming to Cadence",
      "diagnostics" => %{"protocol" => "tcp"},
      "extensions" => %{}
    }
  end

  defp opportunity_document do
    %{
      "id" => "opportunity-123",
      "spacecraft_ref" => "SC-001",
      "ground_station_ref" => "station-svalbard",
      "antenna_or_service_pool_ref" => "station-svalbard-antenna-1",
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => "2026-07-13T12:10:00Z",
      "ends_at" => "2026-07-13T12:20:00Z",
      "expires_at" => "2026-07-13T12:09:00Z",
      "availability" => "available",
      "synthetic" => true,
      "extensions" => %{}
    }
  end

  defp contact_document do
    %{
      "id" => "contact-123",
      "client_reference" => "cadence-reservation-123",
      "opportunity_ref" => "opportunity-123",
      "spacecraft_ref" => "SC-001",
      "ground_station_ref" => "station-svalbard",
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "delivery_profile_ref" => "delivery-cadence-primary",
      "starts_at" => "2026-07-13T12:10:00Z",
      "ends_at" => "2026-07-13T12:20:00Z",
      "status" => "confirmed",
      "pass_phase" => "prepass",
      "delivery" => %{
        "status" => "ready",
        "direction" => "downlink",
        "delivery_kind" => "realtime_stream",
        "mode" => "provider_connects",
        "protocol" => "tcp",
        "endpoint_ref" => "delivery-cadence-primary",
        "framing" => %{"family" => "ccsds_tm", "mode" => "fixed_size", "frame_bytes" => 1115},
        "allowed_source_refs" => ["SC-001"],
        "activation_window" => %{
          "starts_at" => "2026-07-13T12:09:30Z",
          "ends_at" => "2026-07-13T12:20:30Z"
        },
        "credential_ref" => nil,
        "diagnostics" => %{}
      },
      "status_reason" => nil,
      "tags" => %{},
      "extensions" => %{}
    }
  end
end
