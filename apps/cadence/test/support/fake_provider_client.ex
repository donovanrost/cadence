defmodule Cadence.TestSupport.FakeProviderClient do
  @moduledoc false

  @behaviour Cadence.Contacts.ProviderClient

  alias Cadence.GroundNetworks.{
    DeliveryDescriptor,
    DeliveryProfile,
    Opportunity,
    ProviderCapabilities,
    ProviderContact,
    ServiceProfile
  }

  @capabilities_document %{
    "contract_version" => "1.0",
    "provider" => %{"type" => "fake", "display_name" => "Fake Provider", "simulated" => true},
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

  @impl true
  def validate_connection(_context, opts) do
    resolve_response(opts, :validate_response, fn -> {:ok, %{"state" => "running"}} end)
  end

  @impl true
  def capabilities(_context, opts) do
    resolve_response(opts, :capabilities_response, fn ->
      ProviderCapabilities.from_external(@capabilities_document)
    end)
  end

  @impl true
  def list_spacecraft(_context, _params, opts) do
    resolve_response(opts, :spacecraft_response, fn -> {:ok, []} end)
  end

  @impl true
  def list_ground_stations(_context, _params, opts) do
    resolve_response(opts, :ground_stations_response, fn -> {:ok, []} end)
  end

  @impl true
  def list_service_profiles(_context, _params, opts) do
    resolve_response(opts, :service_profiles_response, fn -> {:ok, [service_profile()]} end)
  end

  @impl true
  def list_delivery_profiles(_context, _params, opts) do
    resolve_response(opts, :delivery_profiles_response, fn -> {:ok, [delivery_profile()]} end)
  end

  @impl true
  def provision_delivery_profile(_context, attrs, opts) do
    run_observer(opts, :on_provision_delivery_profile, attrs)

    resolve_response(opts, :provision_delivery_profile_response, fn ->
      {:ok, delivery_profile()}
    end)
  end

  @impl true
  def search_opportunities(_context, params, opts) do
    run_observer(opts, :on_search, params)

    resolve_response(opts, :search_response, fn ->
      {:ok, %{data: [opportunity(params)], next_cursor: nil, truncated: false}}
    end)
  end

  @impl true
  def reserve_contact(_context, attrs, opts) do
    run_observer(opts, :on_reserve, attrs)
    resolve_response(opts, :reserve_response, fn -> {:ok, contact(attrs, opts, :confirmed)} end)
  end

  @impl true
  def describe_contact(_context, provider_contact_id, opts) do
    run_observer(opts, :on_describe, provider_contact_id)

    resolve_response(opts, :describe_response, fn ->
      {:ok,
       contact(
         %{
           "client_reference" => "described-contact",
           "opportunity_ref" => "opportunity-alpha",
           "spacecraft_ref" => "SC-001",
           "service_profile_ref" => "service-realtime-ttc-downlink",
           "delivery_profile_ref" => "delivery-cadence-primary"
         },
         Keyword.put(opts, :provider_contact_id, provider_contact_id),
         :confirmed
       )}
    end)
  end

  @impl true
  def modify_contact(_context, provider_contact_id, attrs, opts) do
    run_observer(opts, :on_modify, %{provider_contact_id: provider_contact_id, attrs: attrs})

    resolve_response(opts, :modify_response, fn ->
      window = %{
        starts_at: parse_time(attrs["starts_at"], default_window().starts_at),
        ends_at: parse_time(attrs["ends_at"], default_window().ends_at)
      }

      contact_attrs = %{
        "client_reference" => attrs["client_reference"],
        "opportunity_ref" => "opportunity-alpha",
        "spacecraft_ref" => "SC-001",
        "service_profile_ref" => "service-realtime-ttc-downlink",
        "delivery_profile_ref" => "delivery-cadence-primary"
      }

      {:ok,
       contact(
         contact_attrs,
         opts
         |> Keyword.put(:provider_contact_id, provider_contact_id)
         |> Keyword.put(:provider_revision, attrs["expected_revision"] + 1)
         |> Keyword.put(:contact_window, window),
         :confirmed
       )}
    end)
  end

  @impl true
  def cancel_contact(_context, provider_contact_id, opts) do
    run_observer(opts, :on_cancel, provider_contact_id)

    resolve_response(opts, :cancel_response, fn ->
      {:ok,
       contact(
         %{
           "client_reference" => "canceled-contact",
           "opportunity_ref" => "opportunity-alpha",
           "spacecraft_ref" => "SC-001",
           "service_profile_ref" => "service-realtime-ttc-downlink",
           "delivery_profile_ref" => "delivery-cadence-primary"
         },
         Keyword.put(opts, :provider_contact_id, provider_contact_id),
         :canceled
       )}
    end)
  end

  @impl true
  def find_contact_by_client_reference(_context, client_reference, opts) do
    run_observer(opts, :on_recover, client_reference)
    resolve_response(opts, :recover_response, fn -> {:error, :provider_contact_not_found} end)
  end

  @impl true
  def events(_context, cursor, opts) do
    resolve_response(opts, :events_response, fn ->
      {:ok, %{data: [], next_cursor: cursor, truncated: false}}
    end)
  end

  defp opportunity(params) do
    {:ok, starts_at, _offset} = DateTime.from_iso8601(params["starts_at"])
    {:ok, ends_at, _offset} = DateTime.from_iso8601(params["ends_at"])
    spacecraft_ref = List.first(params["spacecraft_refs"]) || "SC-001"

    %Opportunity{
      id: "opportunity-alpha",
      spacecraft_ref: spacecraft_ref,
      ground_station_ref: "station-alpha",
      antenna_or_service_pool_ref: "station-alpha-antenna-1",
      service_profile_ref: params["service_profile_ref"],
      starts_at: DateTime.add(starts_at, 60),
      ends_at: DateTime.add(ends_at, -60),
      expires_at: starts_at,
      availability: :available,
      synthetic: true,
      extensions: %{},
      evidence: %{}
    }
  end

  defp contact(attrs, opts, status) do
    window = Keyword.get(opts, :contact_window, default_window())
    starts_at = window[:starts_at]
    ends_at = window[:ends_at]
    provider_contact_id = Keyword.get(opts, :provider_contact_id, "provider-contact-alpha")
    delivery_status = if status == :canceled, do: :ended, else: :ready

    %ProviderContact{
      id: provider_contact_id,
      provider_revision: Keyword.get(opts, :provider_revision, 1),
      client_reference: attrs["client_reference"],
      opportunity_ref: attrs["opportunity_ref"],
      spacecraft_ref: attrs["spacecraft_ref"],
      ground_station_ref: "station-alpha",
      antenna_or_service_pool_ref: "station-alpha-antenna-1",
      service_profile_ref: attrs["service_profile_ref"],
      delivery_profile_ref: attrs["delivery_profile_ref"],
      starts_at: starts_at,
      ends_at: ends_at,
      status: status,
      provider_status: Atom.to_string(status),
      pass_phase: if(status == :canceled, do: :closed, else: :scheduled),
      delivery: delivery_descriptor(attrs, starts_at, ends_at, delivery_status),
      tags: %{},
      extensions: %{},
      evidence: %{}
    }
  end

  defp delivery_descriptor(attrs, starts_at, ends_at, status) do
    evidence = %{
      "status" => Atom.to_string(status),
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "mode" => "provider_connects",
      "protocol" => "tcp",
      "endpoint_ref" => attrs["delivery_profile_ref"],
      "framing" => %{"family" => "ccsds_tm", "mode" => "fixed_size", "frame_bytes" => 1115},
      "allowed_source_refs" => [attrs["spacecraft_ref"]],
      "activation_window" => %{
        "starts_at" => DateTime.to_iso8601(starts_at),
        "ends_at" => DateTime.to_iso8601(ends_at)
      },
      "credential_ref" => nil,
      "diagnostics" => %{}
    }

    %DeliveryDescriptor{
      status: status,
      direction: :downlink,
      delivery_kind: "realtime_stream",
      mode: "provider_connects",
      protocol: "tcp",
      endpoint_ref: attrs["delivery_profile_ref"],
      framing: evidence["framing"],
      allowed_source_refs: [attrs["spacecraft_ref"]],
      activation_window: evidence["activation_window"],
      diagnostics: %{},
      evidence: evidence
    }
  end

  defp service_profile do
    %ServiceProfile{
      id: "service-realtime-ttc-downlink",
      version: 1,
      display_name: "Realtime TT&C downlink",
      service_kind: "realtime_telemetry",
      direction: :downlink,
      supported_delivery_kinds: ["realtime_stream"],
      data_families: ["ccsds_tm"],
      minimum_duration_seconds: 30,
      state: :active
    }
  end

  defp delivery_profile do
    %DeliveryProfile{
      id: "delivery-cadence-primary",
      version: 1,
      display_name: "Cadence primary telemetry ingress",
      direction: :downlink,
      delivery_kind: "realtime_stream",
      supported_service_profile_refs: ["service-realtime-ttc-downlink"],
      state: :ready,
      operator_summary: "Streaming to Cadence"
    }
  end

  defp default_window do
    starts_at = DateTime.utc_now()
    %{starts_at: starts_at, ends_at: DateTime.add(starts_at, 600)}
  end

  defp parse_time(nil, default), do: default

  defp parse_time(value, _default) when is_binary(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime
  end

  defp run_observer(opts, key, value) do
    case Keyword.get(opts, key) do
      fun when is_function(fun, 1) -> fun.(value)
      _other -> :ok
    end
  end

  defp resolve_response(opts, key, default) do
    case Keyword.get(opts, key) do
      fun when is_function(fun, 0) -> fun.()
      fun when is_function(fun, 1) -> fun.(opts)
      nil -> default.()
      response -> response
    end
  end
end
