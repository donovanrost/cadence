defmodule Cadence.Dashboards.Sources.OperationalObservablesFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Commanding.CommandQueueEntry
  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{RealizedContact, ScheduledContact}

  alias Cadence.Dashboards.{Field, PlannedSourceRequest, ResolvedSourceBinding}

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Dashboards.Sources.OperationalObservables
  alias Cadence.Limits.Event
  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  def source_request do
    %PlannedSourceRequest{
      request_id: "ops-request-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :operational_observables,
      observables: [],
      data_context: %{realm: :flight},
      sampling: %{mode: :constellation_health}
    }
  end

  def assert_replay_operational_observable_opts(opts, from_time, to_time) do
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time
  end

  def source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "flight-operational-observables",
        realm: :flight,
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables",
        dataset: "operational_observables"
      },
      data_source: %DataSource{
        data_source_id: "managed_operational_observables",
        adapter: OperationalObservables
      },
      realm: :flight,
      dataset: "operational_observables"
    }
  end

  def replay_source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "replay-operational-observables",
        realm: :replay,
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables_replay",
        dataset: "operational_observables_replay"
      },
      data_source: %DataSource{
        data_source_id: "managed_operational_observables_replay",
        adapter: OperationalObservables
      },
      realm: :replay,
      dataset: "operational_observables_replay"
    }
  end

  def managed_runtime_event(event_id, source_record_kind, kind, occurred_at, opts) do
    runtime_fact_id = Keyword.fetch!(opts, :runtime_fact_id)

    capability_instance_id =
      Keyword.get(opts, :capability_instance_id, "managed-capability-alpha")

    OperationalEvent.new(%{
      event_id: event_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      occurred_at: occurred_at,
      recorded_at: occurred_at,
      effective_at: occurred_at,
      category: :runtime,
      kind: kind,
      severity: :info,
      actor: %{kind: :replay, id: "replay-run-1"},
      subject: %{kind: :capability_instance, id: capability_instance_id},
      scope: %{
        replay_run_id: "replay-run-1",
        capability_instance_id: capability_instance_id,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha"
      },
      causality: %{
        replay_run_id: "replay-run-1",
        correlation_id: capability_instance_id,
        source_record_kind: source_record_kind,
        source_record_id: runtime_fact_id
      },
      payload:
        %{
          replay_run_id: "replay-run-1",
          capability_instance_id: capability_instance_id,
          family_key: :packet_counter,
          activation_id: "activation-alpha",
          binding_set_id: "binding-set-alpha",
          binding_set_version: 1,
          partition_affinity: :spacecraft,
          partition_value: "spacecraft-alpha",
          packet_id: "packet-alpha",
          evidence_id: "evidence-alpha"
        }
        |> Map.merge(
          Map.take(Map.new(opts), [
            :timer_key,
            :action_kind,
            :event_kind,
            :emitted_record_kinds,
            :emitted_record_count,
            :action_request_count,
            :state_snapshot,
            :record_metadata,
            :request_document
          ])
        ),
      current: %{}
    })
  end

  def transport_runtime_event(event_id, source_record_kind, kind, occurred_at, opts) do
    runtime_fact_id = Keyword.fetch!(opts, :runtime_fact_id)

    capability_instance_id =
      Keyword.get(opts, :capability_instance_id, "transport-alpha")

    OperationalEvent.new(%{
      event_id: event_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      occurred_at: occurred_at,
      recorded_at: occurred_at,
      effective_at: occurred_at,
      category: :comms,
      kind: kind,
      severity: :info,
      actor: %{kind: :replay, id: "replay-run-1"},
      subject: %{kind: :transport, id: capability_instance_id},
      scope: %{
        replay_run_id: "replay-run-1",
        contact_id: "replay-contact-alpha",
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        capability_instance_id: capability_instance_id,
        source_endpoint_ref: Keyword.get(opts, :source_endpoint_ref),
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-alpha"
      },
      causality: %{
        replay_run_id: "replay-run-1",
        correlation_id: capability_instance_id,
        source_record_kind: source_record_kind,
        source_record_id: runtime_fact_id
      },
      payload:
        %{
          replay_run_id: "replay-run-1",
          contact_id: "replay-contact-alpha",
          realized_contact_id: "replay-contact-alpha",
          path_id: "replay-uplink-path",
          capability_instance_id: capability_instance_id,
          source_endpoint_ref: Keyword.get(opts, :source_endpoint_ref),
          family_key: :uplink_gateway,
          activation_id: "transport-activation-alpha",
          binding_set_id: "transport-binding-set-alpha",
          binding_set_version: 1,
          partition_affinity: :source_endpoint,
          partition_value: "endpoint-alpha"
        }
        |> Map.merge(
          Map.take(Map.new(opts), [
            :timer_key,
            :action_kind,
            :command_release_attempt_id,
            :command_request_id,
            :command_name,
            :signal_phase,
            :event_kind,
            :emitted_record_kinds,
            :emitted_record_count,
            :action_request_count,
            :state_snapshot,
            :record_metadata,
            :request_document,
            :action_metadata,
            :timer_metadata
          ])
        ),
      current: %{}
    })
  end

  def spacecraft(spacecraft_id) do
    %Spacecraft{
      organization_id: "org-1",
      mission_id: "mission-1",
      spacecraft_id: spacecraft_id,
      display_name: spacecraft_id
    }
  end

  def scheduled_contact(scheduled_contact_id, lifecycle_state, opts \\ []) do
    %ScheduledContact{
      organization_id: "org-1",
      mission_id: "mission-1",
      scheduled_contact_id: scheduled_contact_id,
      realized_contact_id: Keyword.get(opts, :realized_contact_id),
      lifecycle_state: lifecycle_state,
      source_endpoint_refs: Keyword.get(opts, :source_endpoint_refs, ["source-endpoint-alpha"]),
      starts_at: Keyword.get(opts, :starts_at, ~U[2026-06-17 12:00:00Z])
    }
  end

  def realized_contact(realized_contact_id, lifecycle_state, opts \\ []) do
    %RealizedContact{
      organization_id: "org-1",
      mission_id: "mission-1",
      realized_contact_id: realized_contact_id,
      scheduled_contact_id: Keyword.get(opts, :scheduled_contact_id),
      lifecycle_state: lifecycle_state,
      source_endpoint_refs: Keyword.get(opts, :source_endpoint_refs, ["source-endpoint-alpha"]),
      realized_at: ~U[2026-06-17 12:00:01Z]
    }
  end

  def transport(transport_id, display_name, opts) do
    Transport.new(%{
      transport_id: transport_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      display_name: display_name,
      transport_kind: :tcp_socket,
      direction_capability: :bidirectional,
      adapter_key: :tcp_socket,
      configuration: %{},
      metadata: Map.new(opts, fn {key, value} -> {Atom.to_string(key), value} end)
    })
  end

  def source_endpoint(source_endpoint_id, display_name, opts \\ []) do
    SourceEndpoint.new(%{
      source_endpoint_id: source_endpoint_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      display_name: display_name,
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      metadata: Map.new(opts, fn {key, value} -> {Atom.to_string(key), value} end)
    })
  end

  def command_queue_entry(entry_id, source_endpoint_ref, lifecycle_state) do
    CommandQueueEntry.new(%{
      command_queue_entry_id: entry_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      command_request_id: "command-request-#{entry_id}",
      source_endpoint_ref: source_endpoint_ref,
      queue_lane_key: source_endpoint_ref,
      lifecycle_state: lifecycle_state,
      enqueued_at: ~U[2026-06-17 12:00:00Z]
    })
  end

  def transport_execution_interval(
        interval_id,
        transport_id,
        event_kind,
        starts_at,
        ends_at,
        opts \\ []
      ) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      kind: :transport_execution,
      subject_kind: :transport,
      subject_id: transport_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: Keyword.get(opts, :source_event_id, "event-#{interval_id}"),
      payload: %{
        "capability_instance_id" => transport_id,
        "transport_record_id" => Keyword.get(opts, :transport_record_id, "record-#{interval_id}"),
        "source_endpoint_id" => Keyword.get(opts, :source_endpoint_id, "endpoint-alpha"),
        "ground_station_id" => Keyword.get(opts, :ground_station_id, "dss-14"),
        "link_assignment_id" => Keyword.get(opts, :link_id, "link-alpha"),
        "contact_id" => Keyword.get(opts, :contact_id, "contact-alpha"),
        "path_id" => Keyword.get(opts, :path_id, "uplink-alpha"),
        "event_kind" => Atom.to_string(event_kind)
      }
    }
  end

  def operational_event_link_ids(frame) do
    frame.meta
    |> Map.get(:links, [])
    |> Enum.filter(&(&1.target == :operational_event))
    |> Enum.map(& &1.target_id)
  end

  def evidence_identities(frame) do
    frame.meta
    |> Map.get(:evidence_refs, [])
    |> Enum.map(&{&1.kind, &1.id})
  end

  def operational_event_evidence_ids(frame) do
    frame.meta
    |> Map.get(:evidence_refs, [])
    |> Enum.filter(&(&1.kind == :operational_event))
    |> Enum.map(& &1.id)
  end

  def field_values(frame, field_name) do
    frame.fields
    |> Enum.find(&(&1.name == field_name))
    |> case do
      %Field{values: values} -> values
      nil -> []
    end
  end

  def event(spacecraft_id, normalized_state) do
    %Event{
      limit_event_id: "limit-#{spacecraft_id}-#{normalized_state}",
      mission_id: "mission-1",
      spacecraft_id: spacecraft_id,
      point_id: "HK.counter",
      point_name: "HK.counter",
      source_sample_type: :telemetry_sample,
      sample_id: "sample-#{spacecraft_id}",
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 1,
      limit_state: normalized_state,
      normalized_state: normalized_state,
      violation: normalized_state in [:red, :yellow],
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end
end
