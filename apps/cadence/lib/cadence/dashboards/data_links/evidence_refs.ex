defmodule Cadence.Dashboards.DataLinks.EvidenceRefs do
  @moduledoc false

  alias Cadence.Dashboards.EvidenceRef

  @spec telemetry_sample_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def telemetry_sample_evidence_refs(samples) do
    samples
    |> List.wrap()
    |> Enum.map(&telemetry_sample_evidence_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec limit_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def limit_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.map(&limit_event_evidence_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec limit_definition_interval_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def limit_definition_interval_evidence_refs(intervals) do
    intervals
    |> List.wrap()
    |> Enum.flat_map(&limit_definition_interval_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec operational_interval_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def operational_interval_evidence_refs(intervals, opts \\ []) do
    source = Keyword.get(opts, :source, :events)

    intervals
    |> List.wrap()
    |> Enum.flat_map(&operational_interval_evidence_refs_for(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec operational_event_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def operational_event_evidence_refs(events, opts \\ []) do
    source = Keyword.get(opts, :source, :events)

    events
    |> List.wrap()
    |> Enum.map(&operational_event_evidence_ref(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec command_queue_entry_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def command_queue_entry_evidence_refs(entries, opts \\ []) do
    source = Keyword.get(opts, :source, :operational_observables)

    entries
    |> List.wrap()
    |> Enum.map(&command_queue_entry_evidence_ref(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec command_release_attempt_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def command_release_attempt_evidence_refs(attempts, opts \\ []) do
    source = Keyword.get(opts, :source, :operational_observables)

    attempts
    |> List.wrap()
    |> Enum.map(&command_release_attempt_evidence_ref(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec command_verifier_instance_evidence_refs([map() | struct()], keyword()) :: [
          EvidenceRef.t()
        ]
  def command_verifier_instance_evidence_refs(verifier_instances, opts \\ []) do
    source = Keyword.get(opts, :source, :operational_observables)

    verifier_instances
    |> List.wrap()
    |> Enum.map(&command_verifier_instance_evidence_ref(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec command_verifier_matched_record_evidence_refs([map() | struct()], keyword()) :: [
          EvidenceRef.t()
        ]
  def command_verifier_matched_record_evidence_refs(verifier_instances, opts \\ []) do
    source = Keyword.get(opts, :source, :operational_observables)

    verifier_instances
    |> List.wrap()
    |> Enum.map(&command_verifier_matched_record_evidence_ref(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec mission_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def mission_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&mission_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec source_health_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def source_health_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&source_health_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec source_watermark_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def source_watermark_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&source_watermark_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec source_capability_posture_event_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def source_capability_posture_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.map(&source_capability_posture_event_evidence_ref/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec source_binding_interval_evidence_refs([map() | struct()], keyword()) :: [EvidenceRef.t()]
  def source_binding_interval_evidence_refs(intervals, opts \\ []) do
    source = Keyword.get(opts, :source)

    intervals
    |> List.wrap()
    |> Enum.flat_map(&source_binding_interval_evidence_refs_for(&1, source))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec telemetry_revision_decision_event_evidence_refs([map() | struct()]) :: [
          EvidenceRef.t()
        ]
  def telemetry_revision_decision_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&telemetry_revision_decision_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec telemetry_backfill_lifecycle_event_evidence_refs([map() | struct()]) :: [
          EvidenceRef.t()
        ]
  def telemetry_backfill_lifecycle_event_evidence_refs(events) do
    events
    |> List.wrap()
    |> Enum.flat_map(&telemetry_backfill_lifecycle_event_evidence_refs_for/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  @spec contact_evidence_refs([map() | struct()]) :: [EvidenceRef.t()]
  def contact_evidence_refs(contacts) do
    contacts
    |> List.wrap()
    |> Enum.map(&contact_evidence_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  defp telemetry_sample_evidence_ref(sample) do
    cond do
      string_id(attr(sample, :evidence_id)) ->
        %EvidenceRef{
          kind: :raw_evidence,
          id: attr(sample, :evidence_id),
          observed_at: observed_at(sample),
          source: :telemetry,
          confidence: :direct
        }

      string_id(attr(sample, :sample_id)) ->
        %EvidenceRef{
          kind: :telemetry_sample,
          id: attr(sample, :sample_id),
          observed_at: observed_at(sample),
          source: :telemetry,
          confidence: :direct
        }

      true ->
        nil
    end
  end

  defp command_queue_entry_evidence_ref(entry, source) do
    case string_id(attr(entry, :command_queue_entry_id)) do
      nil ->
        nil

      entry_id ->
        %EvidenceRef{
          kind: :command_queue_entry,
          id: entry_id,
          observed_at: attr(entry, :enqueued_at),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp command_release_attempt_evidence_ref(attempt, source) do
    case string_id(attr(attempt, :command_release_attempt_id)) do
      nil ->
        nil

      attempt_id ->
        %EvidenceRef{
          kind: :command_release_attempt,
          id: attempt_id,
          observed_at:
            attr(attempt, :attempted_at) || attr(attempt, :released_at) ||
              attr(attempt, :requested_at) || attr(attempt, :starts_at),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp command_verifier_instance_evidence_ref(verifier_instance, source) do
    case string_id(attr(verifier_instance, :command_verifier_instance_id)) do
      nil ->
        nil

      verifier_instance_id ->
        %EvidenceRef{
          kind: :command_verifier_instance,
          id: verifier_instance_id,
          observed_at:
            attr(verifier_instance, :matched_at) || attr(verifier_instance, :timeout_at) ||
              attr(verifier_instance, :delay_until),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp command_verifier_matched_record_evidence_ref(verifier_instance, source) do
    with kind when not is_nil(kind) <-
           matched_record_evidence_kind(attr(verifier_instance, :matched_record_kind)),
         id when not is_nil(id) <- string_id(attr(verifier_instance, :matched_record_id)) do
      %EvidenceRef{
        kind: kind,
        id: id,
        observed_at: attr(verifier_instance, :matched_at),
        source: normalize_source(source),
        confidence: :direct
      }
    else
      _other -> nil
    end
  end

  defp matched_record_evidence_kind(:telemetry_sample), do: :telemetry_sample
  defp matched_record_evidence_kind("telemetry_sample"), do: :telemetry_sample
  defp matched_record_evidence_kind(:transport_action_request), do: :transport_action_request
  defp matched_record_evidence_kind("transport_action_request"), do: :transport_action_request

  defp matched_record_evidence_kind(:transport_capability_record),
    do: :transport_capability_record

  defp matched_record_evidence_kind("transport_capability_record"),
    do: :transport_capability_record

  defp matched_record_evidence_kind(_other), do: nil

  defp limit_event_evidence_ref(event) do
    case string_id(attr(event, :limit_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :limit_event,
          id: event_id,
          observed_at: observed_at(event),
          source: :limits,
          confidence: :direct
        }
    end
  end

  defp limit_definition_interval_evidence_refs_for(interval) do
    [
      limit_definition_interval_evidence_ref(interval),
      limit_definition_lifecycle_event_evidence_ref(interval),
      limit_definition_evidence_ref(interval)
    ]
  end

  defp limit_definition_interval_evidence_ref(interval) do
    case string_id(attr(interval, :interval_id)) ||
           interval_id(:limit_definition, attr(interval, :definition_activation_key)) do
      nil ->
        nil

      interval_id ->
        %EvidenceRef{
          kind: :limit_definition_interval,
          id: interval_id,
          observed_at: attr(interval, :observed_at) || attr(interval, :active_from),
          source: :limits,
          confidence: limit_definition_interval_confidence(interval)
        }
    end
  end

  defp limit_definition_lifecycle_event_evidence_ref(interval) do
    case string_id(attr(interval, :limit_definition_lifecycle_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :limit_definition_lifecycle_event,
          id: event_id,
          observed_at: attr(interval, :observed_at),
          source: :limits,
          confidence: limit_definition_interval_confidence(interval)
        }
    end
  end

  defp limit_definition_evidence_ref(interval) do
    case string_id(attr(interval, :limit_definition_id)) do
      nil ->
        nil

      definition_id ->
        %EvidenceRef{
          kind: :limit_definition,
          id: definition_id,
          observed_at: attr(interval, :observed_at) || attr(interval, :active_from),
          source: :limits,
          confidence: limit_definition_interval_confidence(interval)
        }
    end
  end

  defp mission_event_evidence_refs_for(event) do
    [
      mission_event_evidence_ref(event),
      mission_event_source_operational_event_evidence_ref(event)
    ]
  end

  defp mission_event_evidence_ref(event) do
    case string_id(attr(event, :mission_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :mission_event,
          id: event_id,
          observed_at: attr(event, :occurred_at),
          source: :events,
          confidence: :projected
        }
    end
  end

  defp mission_event_source_operational_event_evidence_ref(event) do
    if attr(event, :source_record_kind) in [:operational_event, "operational_event"] do
      case string_id(attr(event, :source_record_id)) do
        nil ->
          nil

        event_id ->
          %EvidenceRef{
            kind: :operational_event,
            id: event_id,
            observed_at: attr(event, :occurred_at),
            source: :events,
            confidence: :direct
          }
      end
    end
  end

  defp operational_event_evidence_ref(event, source) do
    case string_id(attr(event, :source_event_id) || attr(event, :event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :operational_event,
          id: event_id,
          observed_at: attr(event, :observed_at) || attr(event, :occurred_at),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp source_health_event_evidence_refs_for(event) do
    [
      source_health_event_evidence_ref(event),
      canonical_operational_event_evidence_ref(
        :source_health_event,
        attr(event, :source_health_event_id),
        attr(event, :observed_at),
        attr(event, :replay_run_id)
      )
    ]
  end

  defp source_health_event_evidence_ref(event) do
    case string_id(attr(event, :source_health_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :source_health_event,
          id: event_id,
          observed_at: attr(event, :observed_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp source_watermark_event_evidence_ref(event) do
    case string_id(attr(event, :source_watermark_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :source_watermark_event,
          id: event_id,
          observed_at: attr(event, :observed_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp source_watermark_event_evidence_refs_for(event) do
    [
      source_watermark_event_evidence_ref(event),
      canonical_operational_event_evidence_ref(
        :source_watermark_event,
        attr(event, :source_watermark_event_id),
        attr(event, :observed_at),
        attr(event, :replay_run_id)
      )
    ]
  end

  defp source_capability_posture_event_evidence_ref(event) do
    case source_capability_posture_operational_event_id(event) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :operational_event,
          id: event_id,
          observed_at: attr(event, :occurred_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp source_binding_interval_evidence_refs_for(interval, source) do
    [
      source_binding_interval_evidence_ref(interval, source),
      source_binding_event_evidence_ref(interval, source),
      source_binding_evidence_ref(interval, source)
    ]
  end

  defp source_binding_interval_evidence_ref(interval, source) do
    interval_id =
      string_id(attr(interval, :interval_id)) ||
        interval_id(:source_binding, attr(interval, :data_binding_event_id))

    case interval_id do
      nil ->
        nil

      interval_id ->
        %EvidenceRef{
          kind: :source_binding_interval,
          id: interval_id,
          observed_at: attr(interval, :started_at) || attr(interval, :active_from),
          source: normalize_source(source),
          confidence: :projected
        }
    end
  end

  defp source_binding_event_evidence_ref(interval, source) do
    case string_id(attr(interval, :data_binding_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :source_binding_event,
          id: event_id,
          observed_at: attr(interval, :started_at),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp source_binding_evidence_ref(interval, source) do
    case string_id(attr(interval, :binding_id)) do
      nil ->
        nil

      binding_id ->
        %EvidenceRef{
          kind: :source_binding,
          id: binding_id,
          observed_at: attr(interval, :started_at) || attr(interval, :active_from),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp telemetry_revision_decision_event_evidence_refs_for(event) do
    [
      telemetry_revision_decision_event_evidence_ref(event),
      canonical_operational_event_evidence_ref(
        :telemetry_observation_identity_decision_event,
        attr(event, :decision_event_id),
        attr(event, :occurred_at) || attr(event, :decided_at)
      )
    ]
  end

  defp telemetry_revision_decision_event_evidence_ref(event) do
    case string_id(attr(event, :decision_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :telemetry_revision_decision_event,
          id: event_id,
          observed_at: attr(event, :occurred_at) || attr(event, :decided_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp telemetry_backfill_lifecycle_event_evidence_refs_for(event) do
    [
      telemetry_backfill_lifecycle_event_evidence_ref(event),
      canonical_operational_event_evidence_ref(
        :telemetry_backfill_lifecycle_event,
        attr(event, :backfill_lifecycle_event_id),
        attr(event, :occurred_at)
      )
    ]
  end

  defp telemetry_backfill_lifecycle_event_evidence_ref(event) do
    case string_id(attr(event, :backfill_lifecycle_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :telemetry_backfill_lifecycle_event,
          id: event_id,
          observed_at: attr(event, :occurred_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp canonical_operational_event_evidence_ref(source_record_kind, source_record_id, observed_at) do
    canonical_operational_event_evidence_ref(
      source_record_kind,
      source_record_id,
      observed_at,
      nil
    )
  end

  defp canonical_operational_event_evidence_ref(
         source_record_kind,
         source_record_id,
         observed_at,
         replay_run_id
       ) do
    case canonical_operational_event_id(source_record_kind, source_record_id, replay_run_id) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :operational_event,
          id: event_id,
          observed_at: observed_at,
          source: :events,
          confidence: :direct
        }
    end
  end

  defp contact_evidence_ref(contact) do
    case string_id(contact_id(contact)) do
      nil ->
        nil

      contact_id ->
        %EvidenceRef{
          kind: contact_kind(contact),
          id: contact_id,
          observed_at: attr(contact, :starts_at) || attr(contact, :realized_at),
          source: :events,
          confidence: :direct
        }
    end
  end

  defp contact_kind(contact) do
    cond do
      attr(contact, :realized_contact_id) -> :realized_contact
      attr(contact, :scheduled_contact_id) -> :scheduled_contact
      true -> :contact
    end
  end

  defp contact_id(contact) do
    attr(contact, :realized_contact_id) || attr(contact, :scheduled_contact_id)
  end

  defp operational_interval_evidence_refs_for(interval, source) do
    [
      operational_interval_evidence_ref(interval, source),
      operational_interval_source_event_evidence_ref(interval, source)
    ]
  end

  defp operational_interval_evidence_ref(interval, source) do
    case string_id(attr(interval, :interval_id)) do
      nil ->
        nil

      interval_id ->
        %EvidenceRef{
          kind: operational_interval_kind(interval),
          id: interval_id,
          observed_at: attr(interval, :starts_at),
          source: normalize_source(source),
          confidence: :projected
        }
    end
  end

  defp operational_interval_source_event_evidence_ref(interval, source) do
    case string_id(attr(interval, :source_event_id)) do
      nil ->
        nil

      event_id ->
        %EvidenceRef{
          kind: :operational_interval,
          id: event_id,
          observed_at: attr(interval, :starts_at),
          source: normalize_source(source),
          confidence: :direct
        }
    end
  end

  defp operational_interval_kind(:binding_set), do: :binding_set_interval
  defp operational_interval_kind("binding_set"), do: :binding_set_interval
  defp operational_interval_kind(:application_binding), do: :application_binding_interval
  defp operational_interval_kind("application_binding"), do: :application_binding_interval
  defp operational_interval_kind(:catalog_revision), do: :catalog_revision_interval
  defp operational_interval_kind("catalog_revision"), do: :catalog_revision_interval
  defp operational_interval_kind(:source_binding), do: :source_binding_interval
  defp operational_interval_kind("source_binding"), do: :source_binding_interval
  defp operational_interval_kind(:source_health), do: :source_health_interval
  defp operational_interval_kind("source_health"), do: :source_health_interval
  defp operational_interval_kind(:transport_execution), do: :transport_execution_interval
  defp operational_interval_kind("transport_execution"), do: :transport_execution_interval

  defp operational_interval_kind(:transport_connection_state),
    do: :transport_connection_state_interval

  defp operational_interval_kind("transport_connection_state"),
    do: :transport_connection_state_interval

  defp operational_interval_kind(:ground_station_connection_state),
    do: :ground_station_connection_state_interval

  defp operational_interval_kind("ground_station_connection_state"),
    do: :ground_station_connection_state_interval

  defp operational_interval_kind(:link_rf_lock_state), do: :link_rf_lock_state_interval
  defp operational_interval_kind("link_rf_lock_state"), do: :link_rf_lock_state_interval

  defp operational_interval_kind(:link_frame_sync_state),
    do: :link_frame_sync_state_interval

  defp operational_interval_kind("link_frame_sync_state"),
    do: :link_frame_sync_state_interval

  defp operational_interval_kind(interval) when is_map(interval) do
    kind = attr(interval, :kind)
    payload = attr(interval, :payload) || %{}

    if kind in [:operational_observable_state, "operational_observable_state"] and
         attr(payload, :observable_id) == "ground.station.antenna_pointing_state" do
      :ground_station_antenna_pointing_state_interval
    else
      operational_interval_kind(kind)
    end
  end

  defp operational_interval_kind(_kind), do: :operational_interval

  defp canonical_operational_event_id(_source_record_kind, nil), do: nil

  defp canonical_operational_event_id(source_record_kind, source_record_id) do
    canonical_operational_event_id(source_record_kind, source_record_id, nil)
  end

  defp canonical_operational_event_id(_source_record_kind, nil, _replay_run_id), do: nil

  defp canonical_operational_event_id(source_record_kind, source_record_id, replay_run_id) do
    case {source_record_kind, string_id(source_record_id)} do
      {:source_capability_posture, "operational_event:" <> _rest = event_id} ->
        event_id

      {:source_capability_posture, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_capability_posture, event_id, replay_run_id)

      {:source_health_event, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_health_event, event_id, replay_run_id)

      {:source_watermark_event, event_id} when is_binary(event_id) ->
        scoped_operational_event_id(:source_watermark_event, event_id, replay_run_id)

      {:telemetry_backfill_lifecycle_event, event_id} when is_binary(event_id) ->
        "operational_event:telemetry_backfill_lifecycle_event:#{event_id}"

      {:telemetry_observation_identity_decision_event, event_id} when is_binary(event_id) ->
        "operational_event:telemetry_observation_identity_decision_event:#{event_id}"

      _other ->
        nil
    end
  end

  defp scoped_operational_event_id(source_record_kind, source_record_id, replay_run_id)
       when is_binary(replay_run_id) and replay_run_id != "" do
    "operational_event:#{source_record_kind}:#{replay_run_id}:#{source_record_id}"
  end

  defp scoped_operational_event_id(source_record_kind, source_record_id, _replay_run_id) do
    "operational_event:#{source_record_kind}:#{source_record_id}"
  end

  defp observed_at(item) do
    attr(item, :receipt_time) || attr(item, :generation_time) || attr(item, :observed_at)
  end

  defp source_capability_posture_operational_event_id(event) do
    attr(event, :event_id) ||
      canonical_operational_event_id(
        :source_capability_posture,
        event |> attr(:causality) |> attr(:source_record_id)
      )
  end

  defp attr(item, key) when is_map(item) and is_atom(key) do
    Map.get(item, key, Map.get(item, Atom.to_string(key)))
  end

  defp attr(_item, _key), do: nil

  defp string_id(value) when is_binary(value) and value != "", do: value
  defp string_id(_value), do: nil

  defp interval_id(kind, event_id) do
    with event_id when is_binary(event_id) and event_id != "" <- string_id(event_id) do
      "effective_interval:#{kind}:#{event_id}"
    end
  end

  defp limit_definition_interval_confidence(interval) do
    case attr(interval, :complete?) do
      false -> :best_effort
      _other -> :direct
    end
  end

  defp normalize_source(source)
       when source in [:telemetry, :limits, :events, :operational_observables],
       do: source

  defp normalize_source(source) when is_binary(source) do
    source
    |> String.replace("-", "_")
    |> case do
      "telemetry" -> :telemetry
      "limits" -> :limits
      "events" -> :events
      "operational_observables" -> :operational_observables
      _other -> nil
    end
  end

  defp normalize_source(_source), do: nil
end
