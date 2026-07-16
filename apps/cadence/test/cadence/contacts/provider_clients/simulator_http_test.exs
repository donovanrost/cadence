defmodule Cadence.Contacts.ProviderClients.SimulatorHTTPTest do
  use ExUnit.Case, async: true

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP

  alias Cadence.GroundNetworks.{
    DeliveryProfile,
    Opportunity,
    ProviderCapabilities,
    ProviderContact,
    ProviderContext,
    ProviderError,
    ProviderEvent
  }

  test "search uses Provider Contract v1 and normalizes its page" do
    params = %{
      "spacecraft_refs" => ["SC-001"],
      "ground_station_refs" => [],
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => "2026-07-13T12:00:00Z",
      "ends_at" => "2026-07-13T13:00:00Z",
      "page_size" => 25
    }

    req_request = fn opts ->
      send(self(), {:request, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "data" => [opportunity_document()],
           "meta" => %{"next_cursor" => "opportunity-123", "truncated" => true}
         }
       }}
    end

    assert {:ok,
            %{
              data: [%Opportunity{id: "opportunity-123", spacecraft_ref: "SC-001"}],
              next_cursor: "opportunity-123",
              truncated: true
            }} =
             SimulatorHTTP.search_opportunities(context(), params, call_opts(req_request))

    assert_received {:request, opts}
    assert opts[:method] == :post
    assert opts[:url] == "http://simulator.test/provider/v1/opportunities/search"
    assert opts[:json] == params
    refute Map.has_key?(opts[:json], "run_id")
    assert {"authorization", "Bearer provider-secret"} in opts[:headers]
    assert {"x-simulator-environment-ref", "environment-alpha"} in opts[:headers]
  end

  test "native reservation sends correlation headers and parses independent lifecycles" do
    attrs = contact_request()

    req_request = fn opts ->
      send(self(), {:request, opts})
      {:ok, %Req.Response{status: 201, body: %{"data" => contact_document()}}}
    end

    assert {:ok,
            %ProviderContact{
              id: "contact-123",
              status: :confirmed,
              pass_phase: :prepass,
              delivery: %{status: :ready, protocol: "tcp"}
            }} =
             SimulatorHTTP.reserve_contact(context(), attrs,
               idempotency_key: "booking-123",
               request_id: "request-123",
               credential_resolver: &resolve_credential/1,
               req_request: req_request
             )

    assert_received {:request, opts}
    assert opts[:url] == "http://simulator.test/provider/v1/contacts"
    assert opts[:json] == attrs
    assert {"idempotency-key", "booking-123"} in opts[:headers]
    assert {"x-request-id", "request-123"} in opts[:headers]
    refute Map.has_key?(opts[:json], "data_plane")
    refute Map.has_key?(opts[:json], "host")
    refute Map.has_key?(opts[:json], "port")
  end

  test "client-reference idempotency omits the native header" do
    req_request = fn opts ->
      send(self(), {:request, opts})
      {:ok, %Req.Response{status: 201, body: %{"data" => contact_document()}}}
    end

    assert {:ok, %ProviderContact{}} =
             SimulatorHTTP.reserve_contact(
               context(idempotency: :client_reference),
               contact_request(),
               call_opts(req_request) ++ [idempotency_key: "must-not-be-sent"]
             )

    assert_received {:request, opts}
    refute Enum.any?(opts[:headers], fn {name, _value} -> name == "idempotency-key" end)
  end

  test "contact modification is capability gated, revision aware, and idempotent" do
    attrs = %{
      "client_reference" => "cadence-change-123",
      "expected_revision" => 1,
      "starts_at" => "2026-07-13T12:11:00Z",
      "ends_at" => "2026-07-13T12:21:00Z",
      "reason" => "operator_requested"
    }

    req_request = fn opts ->
      send(self(), {:request, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"data" => contact_document(revision: 2)}
       }}
    end

    assert {:ok, %ProviderContact{provider_revision: 2}} =
             SimulatorHTTP.modify_contact(
               context(),
               "contact-123",
               attrs,
               call_opts(req_request) ++ [idempotency_key: "change-123"]
             )

    assert_received {:request, opts}
    assert opts[:method] == :patch
    assert opts[:url] == "http://simulator.test/provider/v1/contacts/contact-123"
    assert opts[:json] == attrs
    assert {"idempotency-key", "change-123"} in opts[:headers]
  end

  test "optional operations are capability gated before an HTTP request" do
    req_request = fn _opts -> flunk("unsupported operation reached HTTP") end
    capabilities = capabilities(idempotency: :native)

    context = %{
      context()
      | capabilities: %{
          capabilities
          | operations:
              capabilities.operations
              |> Map.put(:delivery_profile_provisioning, false)
              |> Map.put(:contact_modification, false),
            events: Map.put(capabilities.events, :polling, false),
            reservation: Map.put(capabilities.reservation, :recovery, :none)
        }
    }

    assert {:error, %ProviderError{category: :unsupported_capability}} =
             SimulatorHTTP.provision_delivery_profile(context, %{}, req_request: req_request)

    assert {:error, %ProviderError{category: :unsupported_capability}} =
             SimulatorHTTP.modify_contact(context, "contact-123", %{}, req_request: req_request)

    assert {:error, %ProviderError{category: :unsupported_capability}} =
             SimulatorHTTP.find_contact_by_client_reference(context, "booking-123",
               req_request: req_request
             )

    assert {:error, %ProviderError{category: :unsupported_capability}} =
             SimulatorHTTP.events(context, nil, req_request: req_request)
  end

  test "profile provisioning and client-reference recovery return normalized resources" do
    req_request = fn opts ->
      send(self(), {:request, opts})

      body =
        case {opts[:method], opts[:url]} do
          {:post, "http://simulator.test/provider/v1/delivery-profiles"} ->
            %{"data" => delivery_profile_document()}

          {:get, "http://simulator.test/provider/v1/contacts"} ->
            %{"data" => [contact_document()]}
        end

      {:ok, %Req.Response{status: 200, body: body}}
    end

    assert {:ok, %DeliveryProfile{id: "delivery-cadence-primary", state: :ready}} =
             SimulatorHTTP.provision_delivery_profile(
               context(),
               %{"client_reference" => "primary"},
               call_opts(req_request)
             )

    assert {:ok, %ProviderContact{id: "contact-123"}} =
             SimulatorHTTP.find_contact_by_client_reference(
               context(),
               "cadence-reservation-123",
               call_opts(req_request)
             )

    assert_received {:request, provision_opts}
    assert provision_opts[:json] == %{"client_reference" => "primary"}
    assert_received {:request, recovery_opts}
    assert recovery_opts[:params] == %{"client_reference" => "cadence-reservation-123"}
  end

  test "events preserve the provider cursor envelope" do
    event = %{
      "id" => "event-123",
      "schema_version" => "1.0",
      "sequence" => 123,
      "occurred_at" => "2026-07-13T12:10:00Z",
      "type" => "contact.status_changed",
      "resource_type" => "contact",
      "resource_id" => "contact-123",
      "resource_revision" => 2,
      "request_id" => "request-123",
      "client_reference" => "cadence-reservation-123",
      "data" => %{"from" => "pending", "to" => "confirmed"}
    }

    req_request = fn opts ->
      send(self(), {:request, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "data" => [event],
           "meta" => %{"next_cursor" => "123", "truncated" => false}
         }
       }}
    end

    assert {:ok,
            %{
              data: [
                %ProviderEvent{
                  id: "event-123",
                  sequence: 123,
                  resource_revision: 2,
                  type: "contact.status_changed"
                }
              ],
              next_cursor: "123",
              truncated: false
            }} =
             SimulatorHTTP.events(context(), "122", call_opts(req_request))

    assert_received {:request, opts}
    assert opts[:params] == %{"cursor" => "122"}
  end

  test "structured failures distinguish provider rejection, unavailable, and ambiguous outcomes" do
    rejected = fn _opts ->
      {:ok,
       %Req.Response{
         status: 409,
         body: %{
           "error" => %{
             "code" => "no_capacity",
             "detail" => "antenna unavailable",
             "api_token" => "must-not-leak"
           }
         }
       }}
    end

    assert {:error,
            %ProviderError{
              category: :no_capacity,
              detail: "antenna unavailable",
              evidence: %{
                "error" => %{"api_token" => "[REDACTED]"}
              }
            }} =
             SimulatorHTTP.describe_contact(context(), "contact-123", call_opts(rejected))

    unavailable = fn _opts -> {:error, %Req.TransportError{reason: :econnrefused}} end

    assert {:error, %ProviderError{category: :provider_unavailable, retryable: true}} =
             SimulatorHTTP.describe_contact(context(), "contact-123", call_opts(unavailable))

    uncertain = fn _opts -> {:error, %Req.TransportError{reason: :timeout}} end

    assert {:error, %ProviderError{category: :ambiguous_outcome, retryable: false}} =
             SimulatorHTTP.describe_contact(context(), "contact-123", call_opts(uncertain))
  end

  test "missing environment or credential resolver fails without issuing HTTP" do
    req_request = fn _opts -> flunk("invalid context reached HTTP") end

    assert {:error, %ProviderError{category: :invalid_request}} =
             SimulatorHTTP.validate_connection(
               %{context() | environment_ref: nil},
               call_opts(req_request)
             )

    assert {:error, %ProviderError{detail: "credential resolver is required"}} =
             SimulatorHTTP.validate_connection(context(), req_request: req_request)
  end

  defp context(overrides \\ []) do
    idempotency = Keyword.get(overrides, :idempotency, :native)

    {:ok, context} =
      ProviderContext.new(%{
        provider_ref: "simulator-alpha",
        organization_id: "organization-alpha",
        mission_id: "mission-alpha",
        client_key: "simulator_http",
        base_url: "http://simulator.test",
        credential_ref: "env://SIMULATOR_PROVIDER_TOKEN",
        environment_ref: "environment-alpha",
        capabilities: capabilities(idempotency: idempotency)
      })

    context
  end

  defp capabilities(overrides) do
    idempotency = Keyword.fetch!(overrides, :idempotency)

    document =
      put_in(capabilities_document(), ["reservation", "idempotency"], to_string(idempotency))

    {:ok, capabilities} = ProviderCapabilities.from_external(document)
    capabilities
  end

  defp capabilities_document do
    %{
      "contract_version" => "1.0",
      "provider" => %{"type" => "simulator", "display_name" => "Simulator"},
      "operations" => %{
        "opportunity_search" => true,
        "contact_reservation" => true,
        "contact_modification" => true,
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

  defp call_opts(req_request),
    do: [credential_resolver: &resolve_credential/1, req_request: req_request]

  defp resolve_credential("env://SIMULATOR_PROVIDER_TOKEN"), do: {:ok, "provider-secret"}

  defp contact_request do
    %{
      "opportunity_ref" => "opportunity-123",
      "spacecraft_ref" => "SC-001",
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "delivery_profile_ref" => "delivery-cadence-primary",
      "client_reference" => "cadence-reservation-123",
      "tags" => %{"cadence_mission_ref" => "mission-alpha"}
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
      "extensions" => %{"model" => "deterministic_pass_v1"}
    }
  end

  defp contact_document(opts \\ []) do
    %{
      "id" => "contact-123",
      "revision" => Keyword.get(opts, :revision, 1),
      "client_reference" => "cadence-reservation-123",
      "opportunity_ref" => "opportunity-123",
      "spacecraft_ref" => "SC-001",
      "ground_station_ref" => "station-svalbard",
      "antenna_or_service_pool_ref" => "station-svalbard-antenna-1",
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
        "diagnostics" => %{"endpoint_health" => "healthy"}
      },
      "status_reason" => nil,
      "tags" => %{},
      "extensions" => %{"synthetic" => true}
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
end
