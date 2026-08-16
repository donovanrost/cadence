defmodule Cadence.OperationalEvents do
  @moduledoc """
  Durable operational event store.

  Operational events are the canonical append-only facts that can project into
  mission timelines, dashboard overlays, audit views, and future interval
  projections.
  """

  alias Ecto.Changeset

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Governance
  alias Cadence.OperationalEvents.{EffectiveInterval, Event, EventQuery, ObservableProjections}
  alias Cadence.OperationalEvents.EventRow, as: OperationalEventRow
  alias Cadence.Repo

  @spec persist_event(Event.t()) :: {:ok, Event.t()} | {:error, term()}
  def persist_event(%Event{} = event) do
    persist_event(Repo, event)
  end

  @spec persist_event(module(), Event.t()) :: {:ok, Event.t()} | {:error, term()}
  def persist_event(repo, %Event{} = event) when is_atom(repo) do
    event
    |> OperationalEventRow.changeset()
    |> repo.insert(
      on_conflict: {:replace, OperationalEventRow.upsert_fields()},
      conflict_target: [:event_id]
    )
    |> case do
      {:ok, %OperationalEventRow{} = row} ->
        {:ok, OperationalEventRow.to_domain(row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec persist_events(module(), [Event.t()]) :: {:ok, [Event.t()]} | {:error, term()}
  def persist_events(_repo, []), do: {:ok, []}

  def persist_events(repo, events) when is_atom(repo) and is_list(events) do
    inserted_at = DateTime.utc_now()
    rows = Enum.map(events, &OperationalEventRow.insert_attrs(&1, inserted_at))

    case repo.insert_all(OperationalEventRow, rows,
           on_conflict: {:replace, OperationalEventRow.upsert_fields()},
           conflict_target: [:event_id]
         ) do
      {count, _returned} when count >= 0 -> {:ok, events}
      other -> {:error, other}
    end
  end

  @spec fetch_event(binary()) :: {:ok, Event.t()} | {:error, :not_found}
  defdelegate fetch_event(event_id), to: EventQuery

  @spec fetch_event(binary(), binary(), binary()) :: {:ok, Event.t()} | {:error, :not_found}
  defdelegate fetch_event(organization_id, mission_id, event_id), to: EventQuery

  @doc false
  @spec list_all_events(binary()) :: [Event.t()]
  defdelegate list_all_events(mission_id), to: EventQuery

  @spec list_events(binary(), keyword()) :: [Event.t()]
  def list_events(mission_id, opts \\ []), do: EventQuery.list_events(mission_id, opts)

  @spec list_events(binary(), binary(), keyword()) :: [Event.t()]
  defdelegate list_events(organization_id, mission_id, opts), to: EventQuery
  @spec binding_set_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def binding_set_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_binding_set_intervals(nil, mission_id, opts)
  end

  @spec binding_set_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def binding_set_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_binding_set_intervals(organization_id, mission_id, opts)
  end

  @spec application_binding_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def application_binding_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_application_binding_intervals(nil, mission_id, opts)
  end

  @spec application_binding_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def application_binding_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_application_binding_intervals(organization_id, mission_id, opts)
  end

  @spec catalog_revision_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def catalog_revision_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_catalog_revision_intervals(nil, mission_id, opts)
  end

  @spec catalog_revision_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def catalog_revision_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_catalog_revision_intervals(organization_id, mission_id, opts)
  end

  @spec source_binding_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def source_binding_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_source_binding_intervals(nil, mission_id, opts)
  end

  @spec source_binding_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def source_binding_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_source_binding_intervals(organization_id, mission_id, opts)
  end

  @spec source_health_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def source_health_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_source_health_intervals(nil, mission_id, opts)
  end

  @spec source_health_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def source_health_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_source_health_intervals(organization_id, mission_id, opts)
  end

  @spec transport_execution_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def transport_execution_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_transport_execution_intervals(nil, mission_id, opts)
  end

  @spec transport_execution_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def transport_execution_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_transport_execution_intervals(organization_id, mission_id, opts)
  end

  @spec operational_observable_state_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def operational_observable_state_intervals(mission_id, opts \\ []) do
    ObservableProjections.operational_observable_state_intervals(mission_id, opts)
  end

  @spec operational_observable_state_intervals(binary(), binary(), keyword()) :: [
          EffectiveInterval.t()
        ]
  def operational_observable_state_intervals(organization_id, mission_id, opts) do
    ObservableProjections.operational_observable_state_intervals(
      organization_id,
      mission_id,
      opts
    )
  end

  @spec connection_state_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def connection_state_intervals(mission_id, opts \\ []) do
    ObservableProjections.connection_state_intervals(mission_id, opts)
  end

  @spec connection_state_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def connection_state_intervals(organization_id, mission_id, opts) do
    ObservableProjections.connection_state_intervals(organization_id, mission_id, opts)
  end

  @spec link_rf_state_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def link_rf_state_intervals(mission_id, opts \\ []) do
    ObservableProjections.link_rf_state_intervals(mission_id, opts)
  end

  @spec link_rf_state_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def link_rf_state_intervals(organization_id, mission_id, opts) do
    ObservableProjections.link_rf_state_intervals(organization_id, mission_id, opts)
  end

  @spec operational_observable_metric_samples(binary(), keyword()) :: [map()]
  def operational_observable_metric_samples(mission_id, opts \\ []) do
    ObservableProjections.operational_observable_metric_samples(mission_id, opts)
  end

  @spec operational_observable_metric_samples(binary(), binary(), keyword()) :: [map()]
  def operational_observable_metric_samples(organization_id, mission_id, opts) do
    ObservableProjections.operational_observable_metric_samples(
      organization_id,
      mission_id,
      opts
    )
  end

  defp build_binding_set_intervals(organization_id, mission_id, opts) do
    events =
      if is_binary(organization_id) do
        list_events(organization_id, mission_id,
          kind: :binding_set_activated,
          order: :asc,
          limit: Keyword.get(opts, :event_limit, 1_000)
        )
      else
        list_events(mission_id,
          kind: :binding_set_activated,
          order: :asc,
          limit: Keyword.get(opts, :event_limit, 1_000)
        )
      end

    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      binding_set_interval(event, next_event)
    end)
    |> maybe_filter_binding_set_id(Keyword.get(opts, :binding_set_id))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_application_binding_intervals(organization_id, mission_id, opts) do
    organization_id
    |> build_binding_set_intervals(mission_id, opts)
    |> Enum.flat_map(&application_binding_intervals_for_binding_set(organization_id, &1))
    |> maybe_filter_subject_id(Keyword.get(opts, :binding_rule_id))
    |> maybe_filter_interval_payload(
      :capability_instance_id,
      Keyword.get(opts, :capability_instance_id)
    )
    |> maybe_filter_interval_payload(:application_key, Keyword.get(opts, :application_key))
    |> maybe_filter_interval_payload(:target_scope, Keyword.get(opts, :target_scope))
    |> maybe_filter_interval_payload(
      :source_endpoint_ref,
      Keyword.get(opts, :source_endpoint_ref)
    )
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp application_binding_intervals_for_binding_set(
         organization_id,
         %EffectiveInterval{} = binding_set_interval
       ) do
    binding_set_id = map_value(binding_set_interval.payload, :binding_set_id)
    version = map_value(binding_set_interval.payload, :binding_set_version)

    case fetch_binding_set(
           organization_id,
           binding_set_interval.mission_id,
           binding_set_id,
           version
         ) do
      {:ok, %BindingSet{} = binding_set} ->
        Enum.map(binding_set.rules, fn %BindingRule{} = rule ->
          application_binding_interval(binding_set_interval, binding_set, rule)
        end)

      {:error, _reason} ->
        []
    end
  end

  defp fetch_binding_set(organization_id, mission_id, binding_set_id, version)
       when is_binary(organization_id) do
    Governance.fetch_binding_set(organization_id, mission_id, binding_set_id, version)
  end

  defp fetch_binding_set(_organization_id, mission_id, binding_set_id, version) do
    Governance.fetch_binding_set(mission_id, binding_set_id, version)
  end

  defp build_catalog_revision_intervals(organization_id, mission_id, opts) do
    organization_id
    |> catalog_revision_events(mission_id, opts)
    |> Enum.group_by(&catalog_database_id/1)
    |> Enum.flat_map(fn {_catalog_database_id, revision_events} ->
      revision_events
      |> Enum.sort_by(&event_sort_key/1)
      |> catalog_revision_events_to_intervals()
    end)
    |> maybe_filter_subject_id(Keyword.get(opts, :catalog_revision_id))
    |> maybe_filter_interval_payload(
      :catalog_database_id,
      Keyword.get(opts, :catalog_database_id)
    )
    |> maybe_filter_interval_payload(:catalog_family, Keyword.get(opts, :catalog_family))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp catalog_revision_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: :catalog_revision,
      order: :asc,
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]

    if is_binary(organization_id) do
      list_events(organization_id, mission_id, event_opts)
    else
      list_events(mission_id, event_opts)
    end
  end

  defp catalog_revision_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      catalog_revision_interval(event, next_event)
    end)
  end

  defp build_source_binding_intervals(organization_id, mission_id, opts) do
    organization_id
    |> source_binding_events(mission_id, opts)
    |> Enum.group_by(&source_binding_id/1)
    |> Enum.flat_map(fn {_binding_id, binding_events} ->
      binding_events
      |> Enum.sort_by(&event_sort_key/1)
      |> source_binding_events_to_intervals()
    end)
    |> maybe_filter_source_binding_id(
      Keyword.get(opts, :source_binding_id) || Keyword.get(opts, :binding_id)
    )
    |> maybe_filter_interval_payload(:logical_source, Keyword.get(opts, :logical_source))
    |> maybe_filter_interval_payload(:realm, Keyword.get(opts, :realm))
    |> maybe_filter_interval_payload(:data_source_id, Keyword.get(opts, :data_source_id))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_source_health_intervals(organization_id, mission_id, opts) do
    organization_id
    |> source_health_events(mission_id, opts)
    |> Enum.group_by(&source_health_key/1)
    |> Enum.flat_map(fn {_source_health_key, events} ->
      events
      |> Enum.sort_by(&event_sort_key/1)
      |> source_health_events_to_intervals()
    end)
    |> maybe_filter_subject_id(Keyword.get(opts, :data_source_id))
    |> maybe_filter_interval_payload(:source_binding_id, Keyword.get(opts, :source_binding_id))
    |> maybe_filter_interval_payload(:source_health, Keyword.get(opts, :source_health))
    |> maybe_filter_interval_payload(
      :previous_source_health,
      Keyword.get(opts, :previous_source_health)
    )
    |> maybe_filter_interval_payload(:logical_source, Keyword.get(opts, :logical_source))
    |> maybe_filter_interval_payload(:realm, Keyword.get(opts, :realm))
    |> maybe_filter_interval_payload(:dataset, Keyword.get(opts, :dataset))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_transport_execution_intervals(organization_id, mission_id, opts) do
    organization_id
    |> transport_capability_events(mission_id, opts)
    |> Enum.group_by(&transport_capability_id/1)
    |> Enum.flat_map(fn {_capability_instance_id, events} ->
      events
      |> Enum.sort_by(&event_sort_key/1)
      |> transport_capability_events_to_intervals()
    end)
    |> maybe_filter_subject_id(Keyword.get(opts, :capability_instance_id))
    |> maybe_filter_interval_payload(
      :contact_id,
      Keyword.get(opts, :contact_id) || Keyword.get(opts, :realized_contact_id)
    )
    |> maybe_filter_interval_payload(:path_id, Keyword.get(opts, :path_id))
    |> maybe_filter_interval_payload(:binding_set_id, Keyword.get(opts, :binding_set_id))
    |> maybe_filter_interval_payload(:activation_id, Keyword.get(opts, :activation_id))
    |> maybe_filter_interval_payload(:family_key, Keyword.get(opts, :family_key))
    |> maybe_filter_interval_payload(:event_kind, Keyword.get(opts, :event_kind))
    |> maybe_filter_interval_payload(:timer_key, Keyword.get(opts, :timer_key))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp transport_capability_events(organization_id, mission_id, opts) do
    event_opts = [
      category: :comms,
      source_record_kind: :transport_capability_record,
      kind: [
        :transport_initialized,
        :transport_control_input_handled,
        :transport_event_handled,
        :transport_timer_handled
      ],
      order: :asc,
      replay_run_id: Keyword.get(opts, :replay_run_id, :none),
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]

    if is_binary(organization_id) do
      list_events(organization_id, mission_id, event_opts)
    else
      list_events(mission_id, event_opts)
    end
  end

  defp transport_capability_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      transport_execution_interval(event, next_event)
    end)
  end

  defp source_binding_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: :data_source_binding_event,
      order: :asc,
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]

    if is_binary(organization_id) do
      list_events(organization_id, mission_id, event_opts)
    else
      list_events(mission_id, event_opts)
    end
  end

  defp source_binding_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      source_binding_interval(event, next_event)
    end)
  end

  defp source_health_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: :source_health_event,
      order: :asc,
      replay_run_id: Keyword.get(opts, :replay_run_id, :none),
      limit: Keyword.get(opts, :event_limit, 1_000)
    ]

    if is_binary(organization_id) do
      list_events(organization_id, mission_id, event_opts)
    else
      list_events(mission_id, event_opts)
    end
  end

  defp source_health_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      source_health_interval(event, next_event)
    end)
  end

  defp binding_set_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    binding_set_id = payload_value(event, :binding_set_id) || subject_id(event)

    %EffectiveInterval{
      interval_id: "effective_interval:binding_set:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: :binding_set,
      subject_kind: :binding_set,
      subject_id: binding_set_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: %{
        "binding_set_id" => binding_set_id,
        "binding_set_version" => payload_value(event, :binding_set_version),
        "activation_id" => payload_value(event, :activation_id)
      },
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id)
      }
    }
  end

  defp application_binding_interval(
         %EffectiveInterval{} = binding_set_interval,
         %BindingSet{} = binding_set,
         %BindingRule{} = rule
       ) do
    capability_instance = capability_instance_for_rule(binding_set, rule)
    application_key = application_key(rule, capability_instance)
    target_scope = BindingRule.target_scope(rule)
    source_endpoint_ref = BindingRule.source_endpoint_ref(rule)

    %EffectiveInterval{
      interval_id:
        "effective_interval:application_binding:#{binding_set_interval.source_event_id}:#{rule.binding_rule_id}",
      organization_id: binding_set_interval.organization_id,
      mission_id: binding_set_interval.mission_id,
      kind: :application_binding,
      subject_kind: :application_binding,
      subject_id: rule.binding_rule_id,
      starts_at: binding_set_interval.starts_at,
      ends_at: binding_set_interval.ends_at,
      source_event_id: binding_set_interval.source_event_id,
      superseded_by_event_id: binding_set_interval.superseded_by_event_id,
      payload: %{
        "binding_set_id" => binding_set.binding_set_id,
        "binding_set_version" => binding_set.version,
        "binding_rule_id" => rule.binding_rule_id,
        "capability_instance_id" => BindingRule.capability_instance_id(rule),
        "application_key" => application_key,
        "target_scope" => target_scope,
        "source_endpoint_ref" => source_endpoint_ref,
        "packet_kind" => BindingRule.packet_kind(rule),
        "apid" => BindingRule.apid(rule),
        "priority" => rule.priority,
        "fanout_mode" => rule.fanout_mode,
        "capability_lifecycle_state" => capability_lifecycle_state(capability_instance)
      },
      metadata: %{
        "binding_set_interval_id" => binding_set_interval.interval_id,
        "binding_set_source_event_id" => binding_set_interval.source_event_id,
        "binding_set_superseded_by_event_id" => binding_set_interval.superseded_by_event_id
      }
    }
  end

  defp capability_instance_for_rule(%BindingSet{} = binding_set, %BindingRule{} = rule) do
    case BindingSet.fetch_capability_instance(
           binding_set,
           BindingRule.capability_instance_id(rule)
         ) do
      {:ok, %CapabilityInstance{} = capability_instance} -> capability_instance
      :error -> nil
    end
  end

  defp application_key(%BindingRule{} = rule, %CapabilityInstance{family_key: family_key}),
    do: family_key || rule.handler_key

  defp application_key(%BindingRule{} = rule, nil), do: rule.handler_key

  defp capability_lifecycle_state(%CapabilityInstance{lifecycle_state: lifecycle_state}),
    do: lifecycle_state

  defp capability_lifecycle_state(nil), do: nil

  defp catalog_revision_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    catalog_revision_id = payload_value(event, :catalog_revision_id) || subject_id(event)

    %EffectiveInterval{
      interval_id: "effective_interval:catalog_revision:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: :catalog_revision,
      subject_kind: :catalog_revision,
      subject_id: catalog_revision_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: %{
        "catalog_revision_id" => catalog_revision_id,
        "catalog_database_id" => payload_value(event, :catalog_database_id),
        "revision_number" => payload_value(event, :revision_number),
        "revision_label" => payload_value(event, :revision_label),
        "catalog_family" => payload_value(event, :catalog_family),
        "artifact_id" => payload_value(event, :artifact_id),
        "import_run_id" => payload_value(event, :import_run_id),
        "mission_model_layer_id" => payload_value(event, :mission_model_layer_id),
        "mission_model_revision_id" => payload_value(event, :mission_model_revision_id),
        "content_sha256" => payload_value(event, :content_sha256)
      },
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id)
      }
    }
  end

  defp source_binding_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    binding_id = payload_value(event, :binding_id) || subject_id(event)

    %EffectiveInterval{
      interval_id: "effective_interval:source_binding:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: :source_binding,
      subject_kind: :source_binding,
      subject_id: binding_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: %{
        "binding_id" => binding_id,
        "event_type" => payload_value(event, :event_type),
        "binding_version" => payload_value(event, :binding_version),
        "status" => current_value(event, :status),
        "logical_source" => payload_value(event, :logical_source),
        "realm" => payload_value(event, :data_realm) || payload_value(event, :realm),
        "data_source_id" => payload_value(event, :data_source_id),
        "dataset" => payload_value(event, :dataset),
        "priority" => payload_value(event, :priority),
        "active_from" => payload_value(event, :active_from),
        "active_to" => payload_value(event, :active_to)
      },
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id)
      }
    }
  end

  defp source_health_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    data_source_id = payload_value(event, :data_source_id) || subject_id(event)

    %EffectiveInterval{
      interval_id: "effective_interval:source_health:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: :source_health,
      subject_kind: :data_source,
      subject_id: data_source_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: %{
        "source_health_event_id" => payload_value(event, :source_health_event_id),
        "source_health_key" => payload_value(event, :source_health_key),
        "event_type" => payload_value(event, :event_type),
        "logical_source" => payload_value(event, :logical_source),
        "data_source_id" => data_source_id,
        "source_binding_id" => payload_value(event, :source_binding_id),
        "realm" => payload_value(event, :data_realm) || payload_value(event, :realm),
        "dataset" => payload_value(event, :dataset),
        "source_health" => current_value(event, :source_health),
        "previous_source_health" => payload_value(event, :previous_source_health),
        "reason" => current_value(event, :reason),
        "replay_run_id" =>
          causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id)
      },
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id),
        "replay_run_id" => causality_value(event, :replay_run_id),
        "event_kind" => event.kind
      }
    }
  end

  defp transport_execution_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    capability_instance_id = transport_capability_id(event)

    %EffectiveInterval{
      interval_id: "effective_interval:transport_execution:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: :transport_execution,
      subject_kind: :transport,
      subject_id: capability_instance_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: %{
        "transport_record_id" => payload_value(event, :transport_record_id),
        "contact_id" => payload_value(event, :contact_id),
        "realized_contact_id" => payload_value(event, :realized_contact_id),
        "path_id" => payload_value(event, :path_id),
        "capability_instance_id" => capability_instance_id,
        "binding_set_id" => payload_value(event, :binding_set_id),
        "binding_set_version" => payload_value(event, :binding_set_version),
        "activation_id" => payload_value(event, :activation_id),
        "family_key" => payload_value(event, :family_key),
        "partition_affinity" => payload_value(event, :partition_affinity),
        "partition_value" => payload_value(event, :partition_value),
        "event_kind" => payload_value(event, :event_kind),
        "timer_key" => payload_value(event, :timer_key),
        "emitted_record_kinds" => payload_value(event, :emitted_record_kinds),
        "emitted_record_count" => payload_value(event, :emitted_record_count),
        "action_request_count" => payload_value(event, :action_request_count),
        "replay_run_id" =>
          causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id),
        "state_snapshot" => payload_value(event, :state_snapshot),
        "recorded_at" => payload_value(event, :recorded_at),
        "record_metadata" => payload_value(event, :record_metadata)
      },
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id),
        "replay_run_id" => causality_value(event, :replay_run_id),
        "event_kind" => event.kind
      }
    }
  end

  defp maybe_filter_binding_set_id(intervals, nil), do: intervals
  defp maybe_filter_binding_set_id(intervals, ""), do: intervals

  defp maybe_filter_binding_set_id(intervals, binding_set_id) when is_binary(binding_set_id) do
    Enum.filter(intervals, &(&1.subject_id == binding_set_id))
  end

  defp maybe_filter_source_binding_id(intervals, nil), do: intervals
  defp maybe_filter_source_binding_id(intervals, ""), do: intervals

  defp maybe_filter_source_binding_id(intervals, binding_id) when is_binary(binding_id) do
    Enum.filter(intervals, &(&1.subject_id == binding_id))
  end

  defp maybe_filter_subject_id(intervals, nil), do: intervals
  defp maybe_filter_subject_id(intervals, ""), do: intervals

  defp maybe_filter_subject_id(intervals, subject_id) when is_binary(subject_id) do
    Enum.filter(intervals, &(&1.subject_id == subject_id))
  end

  defp maybe_filter_interval_payload(intervals, _key, nil), do: intervals

  defp maybe_filter_interval_payload(intervals, key, values) when is_list(values) do
    normalized_values = Enum.map(values, &normalize_filter_value/1)

    Enum.filter(intervals, fn %EffectiveInterval{} = interval ->
      normalized_payload_value =
        interval.payload
        |> map_value(key)
        |> normalize_payload_filter_value()

      normalized_payload_value in normalized_values
    end)
  end

  defp maybe_filter_interval_payload(intervals, key, value) do
    normalized_value = normalize_filter_value(value)

    Enum.filter(intervals, fn %EffectiveInterval{} = interval ->
      interval.payload
      |> map_value(key)
      |> normalize_payload_filter_value() == normalized_value
    end)
  end

  defp maybe_filter_at(intervals, nil), do: intervals

  defp maybe_filter_at(intervals, %DateTime{} = at) do
    Enum.filter(intervals, &EffectiveInterval.contains?(&1, at))
  end

  defp order_intervals(intervals, order) when order in [:desc, "desc"] do
    Enum.sort_by(intervals, &interval_sort_key/1, :desc)
  end

  defp order_intervals(intervals, _order) do
    Enum.sort_by(intervals, &interval_sort_key/1, :asc)
  end

  defp interval_sort_key(%EffectiveInterval{} = interval) do
    {DateTime.to_unix(interval.starts_at, :microsecond), interval.interval_id}
  end

  defp event_sort_key(%Event{} = event) do
    {DateTime.to_unix(event.occurred_at, :microsecond), event.event_id}
  end

  defp from_time(opts), do: Keyword.get(opts, :from_time) || Keyword.get(opts, :from_occurred_at)
  defp to_time(opts), do: Keyword.get(opts, :to_time) || Keyword.get(opts, :to_occurred_at)

  defp payload_value(%Event{payload: payload}, key), do: map_value(payload, key)

  defp current_value(%Event{current: current}, key), do: map_value(current, key)
  defp causality_value(%Event{causality: causality}, key), do: map_value(causality, key)

  defp subject_id(%Event{subject: %{id: id}}), do: id
  defp subject_id(%Event{subject: %{"id" => id}}), do: id
  defp subject_id(%Event{}), do: nil

  defp source_binding_id(%Event{} = event),
    do: payload_value(event, :binding_id) || subject_id(event)

  defp source_health_key(%Event{} = event),
    do: payload_value(event, :source_health_key) || subject_id(event)

  defp transport_capability_id(%Event{} = event),
    do: payload_value(event, :capability_instance_id) || subject_id(event)

  defp catalog_database_id(%Event{} = event), do: payload_value(event, :catalog_database_id)

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp normalize_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_filter_value(value) when is_binary(value), do: value

  defp normalize_payload_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_payload_filter_value(value), do: value
end
