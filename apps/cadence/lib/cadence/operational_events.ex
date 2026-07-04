defmodule Cadence.OperationalEvents do
  @moduledoc """
  Durable operational event store.

  Operational events are the canonical append-only facts that can project into
  mission timelines, dashboard overlays, audit views, and future interval
  projections.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Governance
  alias Cadence.OperationalEvents.{EffectiveInterval, Event}
  alias Cadence.Persistence.Schemas.OperationalEventRow
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

  @spec fetch_event(binary()) :: {:ok, Event.t()} | {:error, :not_found}
  def fetch_event(event_id) when is_binary(event_id) do
    case Repo.get(OperationalEventRow, event_id) do
      nil -> {:error, :not_found}
      %OperationalEventRow{} = row -> {:ok, OperationalEventRow.to_domain(row)}
    end
  end

  @spec list_events(binary(), keyword()) :: [Event.t()]
  def list_events(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    OperationalEventRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter_atoms(:category, Keyword.get(opts, :category))
    |> maybe_filter_atoms(:kind, Keyword.get(opts, :kind))
    |> maybe_filter_atoms(:severity, Keyword.get(opts, :severity))
    |> maybe_filter_equals(
      :subject_kind,
      normalize_optional_filter(Keyword.get(opts, :subject_kind))
    )
    |> maybe_filter_equals(:subject_id, Keyword.get(opts, :subject_id))
    |> maybe_filter_equals(
      :source_record_kind,
      normalize_optional_filter(Keyword.get(opts, :source_record_kind))
    )
    |> maybe_filter_equals(:source_record_id, Keyword.get(opts, :source_record_id))
    |> maybe_filter_replay_run_id(Keyword.get(opts, :replay_run_id))
    |> maybe_filter_time_range(opts)
    |> order_by_direction(Keyword.get(opts, :order, :desc))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&OperationalEventRow.to_domain/1)
  end

  @spec list_events(binary(), binary(), keyword()) :: [Event.t()]
  def list_events(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    OperationalEventRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> maybe_filter_atoms(:category, Keyword.get(opts, :category))
    |> maybe_filter_atoms(:kind, Keyword.get(opts, :kind))
    |> maybe_filter_atoms(:severity, Keyword.get(opts, :severity))
    |> maybe_filter_equals(
      :subject_kind,
      normalize_optional_filter(Keyword.get(opts, :subject_kind))
    )
    |> maybe_filter_equals(:subject_id, Keyword.get(opts, :subject_id))
    |> maybe_filter_equals(
      :source_record_kind,
      normalize_optional_filter(Keyword.get(opts, :source_record_kind))
    )
    |> maybe_filter_equals(:source_record_id, Keyword.get(opts, :source_record_id))
    |> maybe_filter_replay_run_id(Keyword.get(opts, :replay_run_id))
    |> maybe_filter_time_range(opts)
    |> order_by_direction(Keyword.get(opts, :order, :desc))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&OperationalEventRow.to_domain/1)
  end

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
  def operational_observable_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_operational_observable_state_intervals(nil, mission_id, opts)
  end

  @spec operational_observable_state_intervals(binary(), binary(), keyword()) :: [
          EffectiveInterval.t()
        ]
  def operational_observable_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_operational_observable_state_intervals(organization_id, mission_id, opts)
  end

  @spec connection_state_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def connection_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_connection_state_intervals(nil, mission_id, opts)
  end

  @spec connection_state_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def connection_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_connection_state_intervals(organization_id, mission_id, opts)
  end

  @spec link_rf_state_intervals(binary(), keyword()) :: [EffectiveInterval.t()]
  def link_rf_state_intervals(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_link_rf_state_intervals(nil, mission_id, opts)
  end

  @spec link_rf_state_intervals(binary(), binary(), keyword()) :: [EffectiveInterval.t()]
  def link_rf_state_intervals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_link_rf_state_intervals(organization_id, mission_id, opts)
  end

  @spec operational_observable_metric_samples(binary(), keyword()) :: [map()]
  def operational_observable_metric_samples(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    build_operational_observable_metric_samples(nil, mission_id, opts)
  end

  @spec operational_observable_metric_samples(binary(), binary(), keyword()) :: [map()]
  def operational_observable_metric_samples(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    build_operational_observable_metric_samples(organization_id, mission_id, opts)
  end

  defp maybe_filter_time_range(query, opts) do
    query
    |> maybe_filter_from_occurred_at(Keyword.get(opts, :from_occurred_at))
    |> maybe_filter_to_occurred_at(Keyword.get(opts, :to_occurred_at))
  end

  defp maybe_filter_from_occurred_at(query, %DateTime{} = from) do
    where(query, [row], row.occurred_at >= ^from)
  end

  defp maybe_filter_from_occurred_at(query, _from), do: query

  defp maybe_filter_to_occurred_at(query, %DateTime{} = to) do
    where(query, [row], row.occurred_at < ^to)
  end

  defp maybe_filter_to_occurred_at(query, _to), do: query

  defp maybe_filter_atoms(query, _field, nil), do: query

  defp maybe_filter_atoms(query, field, values) do
    normalized_values =
      values
      |> List.wrap()
      |> Enum.map(&normalize_filter_value/1)

    where(query, [row], field(row, ^field) in ^normalized_values)
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, values) when is_list(values) do
    normalized_values = Enum.map(values, &normalize_filter_value/1)
    where(query, [row], field(row, ^field) in ^normalized_values)
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp maybe_filter_replay_run_id(query, :none),
    do: where(query, [row], is_nil(row.replay_run_id))

  defp maybe_filter_replay_run_id(query, replay_run_id),
    do: maybe_filter_equals(query, :replay_run_id, replay_run_id)

  defp order_by_direction(query, :asc) do
    order_by(query, [row], asc: row.occurred_at, asc: row.event_id)
  end

  defp order_by_direction(query, "asc"), do: order_by_direction(query, :asc)

  defp order_by_direction(query, _order) do
    order_by(query, [row], desc: row.occurred_at, desc: row.event_id)
  end

  defp normalize_optional_filter(nil), do: nil
  defp normalize_optional_filter(values) when is_list(values), do: values
  defp normalize_optional_filter(value), do: normalize_filter_value(value)

  defp normalize_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_filter_value(value) when is_binary(value), do: value

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

  defp build_operational_observable_state_intervals(organization_id, mission_id, opts) do
    organization_id
    |> operational_observable_state_events(mission_id, opts)
    |> Enum.group_by(&operational_observable_state_key/1)
    |> Enum.flat_map(fn {_key, events} ->
      events
      |> Enum.sort_by(&event_sort_key/1)
      |> operational_observable_state_events_to_intervals()
    end)
    |> maybe_filter_interval_payload(:observable_id, Keyword.get(opts, :observable_id))
    |> maybe_filter_interval_payload(:resource_id, Keyword.get(opts, :resource_id))
    |> maybe_filter_interval_payload(:scope_kind, Keyword.get(opts, :scope_kind))
    |> maybe_filter_interval_payload(:transport_id, Keyword.get(opts, :transport_id))
    |> maybe_filter_interval_payload(:source_endpoint_id, Keyword.get(opts, :source_endpoint_id))
    |> maybe_filter_interval_payload(:ground_station_id, Keyword.get(opts, :ground_station_id))
    |> maybe_filter_interval_payload(:link_id, Keyword.get(opts, :link_id))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_connection_state_intervals(organization_id, mission_id, opts) do
    organization_id
    |> connection_state_events(mission_id, opts)
    |> Enum.group_by(&operational_observable_state_key/1)
    |> Enum.flat_map(fn {_key, events} ->
      events
      |> Enum.sort_by(&event_sort_key/1)
      |> connection_state_events_to_intervals()
    end)
    |> maybe_filter_interval_payload(
      :connection_state_family,
      Keyword.get(opts, :connection_state_family)
    )
    |> maybe_filter_interval_payload(:observable_id, Keyword.get(opts, :observable_id))
    |> maybe_filter_interval_payload(:resource_id, Keyword.get(opts, :resource_id))
    |> maybe_filter_interval_payload(:scope_kind, Keyword.get(opts, :scope_kind))
    |> maybe_filter_interval_payload(:transport_id, Keyword.get(opts, :transport_id))
    |> maybe_filter_interval_payload(:source_endpoint_id, Keyword.get(opts, :source_endpoint_id))
    |> maybe_filter_interval_payload(:ground_station_id, Keyword.get(opts, :ground_station_id))
    |> maybe_filter_interval_payload(:link_id, Keyword.get(opts, :link_id))
    |> maybe_filter_interval_payload(:connection_state, Keyword.get(opts, :connection_state))
    |> maybe_filter_interval_payload(:normalized_state, Keyword.get(opts, :normalized_state))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_link_rf_state_intervals(organization_id, mission_id, opts) do
    organization_id
    |> link_rf_state_events(mission_id, opts)
    |> Enum.group_by(&operational_observable_state_key/1)
    |> Enum.flat_map(fn {_key, events} ->
      events
      |> Enum.sort_by(&event_sort_key/1)
      |> link_rf_state_events_to_intervals()
    end)
    |> maybe_filter_interval_payload(:rf_state_family, Keyword.get(opts, :rf_state_family))
    |> maybe_filter_interval_payload(:observable_id, Keyword.get(opts, :observable_id))
    |> maybe_filter_interval_payload(:resource_id, Keyword.get(opts, :resource_id))
    |> maybe_filter_interval_payload(:scope_kind, Keyword.get(opts, :scope_kind))
    |> maybe_filter_interval_payload(:transport_id, Keyword.get(opts, :transport_id))
    |> maybe_filter_interval_payload(:source_endpoint_id, Keyword.get(opts, :source_endpoint_id))
    |> maybe_filter_interval_payload(:ground_station_id, Keyword.get(opts, :ground_station_id))
    |> maybe_filter_interval_payload(:link_id, Keyword.get(opts, :link_id))
    |> maybe_filter_interval_payload(:state, Keyword.get(opts, :state))
    |> maybe_filter_interval_payload(:normalized_state, Keyword.get(opts, :normalized_state))
    |> maybe_filter_at(Keyword.get(opts, :at))
    |> Enum.filter(&EffectiveInterval.overlaps?(&1, from_time(opts), to_time(opts)))
    |> order_intervals(Keyword.get(opts, :order, :asc))
  end

  defp build_operational_observable_metric_samples(organization_id, mission_id, opts) do
    organization_id
    |> operational_observable_metric_events(mission_id, opts)
    |> Enum.map(&operational_observable_metric_sample/1)
    |> maybe_filter_sample_payload(:observable_id, Keyword.get(opts, :observable_id))
    |> maybe_filter_sample_payload(:resource_id, Keyword.get(opts, :resource_id))
    |> maybe_filter_sample_payload(:scope_kind, Keyword.get(opts, :scope_kind))
    |> maybe_filter_sample_payload(:transport_id, Keyword.get(opts, :transport_id))
    |> maybe_filter_sample_payload(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> maybe_filter_sample_payload(
      :contact_id,
      Keyword.get(opts, :contact_id) || Keyword.get(opts, :scheduled_contact_id) ||
        Keyword.get(opts, :realized_contact_id)
    )
    |> maybe_filter_sample_payload(:source_endpoint_id, Keyword.get(opts, :source_endpoint_id))
    |> maybe_filter_sample_payload(:ground_station_id, Keyword.get(opts, :ground_station_id))
    |> maybe_filter_sample_payload(:link_id, Keyword.get(opts, :link_id))
    |> order_samples(Keyword.get(opts, :order, :asc))
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

  defp operational_observable_state_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: operational_observable_state_source_record_kinds(),
      kind: :operational_observable_state_changed,
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

  defp connection_state_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: :connection_state_snapshot,
      kind: :operational_observable_state_changed,
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

  defp link_rf_state_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: [:link_rf_lock_state_snapshot, :link_frame_sync_state_snapshot],
      kind: :operational_observable_state_changed,
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

  defp operational_observable_state_source_record_kinds do
    [
      :connection_state_snapshot,
      :link_rf_lock_state_snapshot,
      :link_frame_sync_state_snapshot,
      :operational_observable_snapshot
    ]
  end

  defp operational_observable_metric_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: :operational_observable_snapshot,
      kind: :operational_observable_metric_sampled,
      from_occurred_at: from_time(opts),
      to_occurred_at: to_time(opts),
      order: Keyword.get(opts, :order, :asc),
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

  defp operational_observable_state_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      operational_observable_state_interval(event, next_event)
    end)
  end

  defp connection_state_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      connection_state_interval(event, next_event)
    end)
  end

  defp link_rf_state_events_to_intervals(events) do
    events
    |> Enum.with_index()
    |> Enum.map(fn {%Event{} = event, index} ->
      next_event = Enum.at(events, index + 1)
      link_rf_state_interval(event, next_event)
    end)
  end

  defp source_binding_events(organization_id, mission_id, opts) do
    event_opts = [
      source_record_kind: :dashboard_data_binding_event,
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
        "telemetry_snapshot_id" => payload_value(event, :telemetry_snapshot_id),
        "command_snapshot_id" => payload_value(event, :command_snapshot_id),
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
        "realm" => payload_value(event, :realm),
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

  defp operational_observable_state_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    observable_id = payload_value(event, :observable_id)
    resource_id = payload_value(event, :resource_id) || subject_id(event)

    %EffectiveInterval{
      interval_id: "effective_interval:operational_observable_state:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: :operational_observable_state,
      subject_kind: subject_kind(event),
      subject_id: resource_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: %{
        "observable_id" => observable_id,
        "resource_id" => resource_id,
        "scope_kind" => payload_value(event, :scope_kind),
        "transport_id" => payload_value(event, :transport_id),
        "source_endpoint_id" => payload_value(event, :source_endpoint_id),
        "ground_station_id" => payload_value(event, :ground_station_id),
        "link_id" => payload_value(event, :link_id),
        "adapter_key" => payload_value(event, :adapter_key),
        "connection_state" => payload_value(event, :connection_state),
        "state" => payload_value(event, :state),
        "normalized_state" => payload_value(event, :normalized_state),
        "observed_at" => payload_value(event, :observed_at),
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

  defp connection_state_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    observable_id = payload_value(event, :observable_id)
    resource_id = payload_value(event, :resource_id) || subject_id(event)
    interval_kind = connection_interval_kind(observable_id)

    %EffectiveInterval{
      interval_id: "effective_interval:#{interval_kind}:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: interval_kind,
      subject_kind: connection_subject_kind(observable_id),
      subject_id: resource_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: connection_state_payload(event, observable_id, resource_id),
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id),
        "replay_run_id" => causality_value(event, :replay_run_id),
        "event_kind" => event.kind
      }
    }
  end

  defp connection_state_payload(%Event{} = event, observable_id, resource_id) do
    connection_state = payload_value(event, :connection_state)

    %{
      "observable_id" => observable_id,
      "resource_id" => resource_id,
      "scope_kind" => payload_value(event, :scope_kind),
      "transport_id" => payload_value(event, :transport_id),
      "source_endpoint_id" => payload_value(event, :source_endpoint_id),
      "ground_station_id" => payload_value(event, :ground_station_id),
      "link_id" => payload_value(event, :link_id),
      "adapter_key" => payload_value(event, :adapter_key),
      "connection_state_family" => connection_state_family(observable_id),
      "transport_connection_state" => transport_connection_state(observable_id, connection_state),
      "ground_station_connection_state" =>
        ground_station_connection_state(observable_id, connection_state),
      "connection_state" => connection_state,
      "state" => payload_value(event, :state),
      "normalized_state" => payload_value(event, :normalized_state),
      "observed_at" => payload_value(event, :observed_at),
      "replay_run_id" =>
        causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id)
    }
  end

  defp connection_interval_kind("comms.transport.connection_state"),
    do: :transport_connection_state

  defp connection_interval_kind("ground.station.connection_state"),
    do: :ground_station_connection_state

  defp connection_subject_kind("comms.transport.connection_state"), do: :transport
  defp connection_subject_kind("ground.station.connection_state"), do: :ground_station

  defp connection_state_family("comms.transport.connection_state"), do: :transport
  defp connection_state_family("ground.station.connection_state"), do: :ground_station

  defp transport_connection_state("comms.transport.connection_state", state), do: state
  defp transport_connection_state(_observable_id, _state), do: nil

  defp ground_station_connection_state("ground.station.connection_state", state), do: state
  defp ground_station_connection_state(_observable_id, _state), do: nil

  defp link_rf_state_interval(%Event{} = event, next_event) do
    starts_at = event.effective_at || event.occurred_at
    ends_at = next_event && (next_event.effective_at || next_event.occurred_at)
    observable_id = payload_value(event, :observable_id)
    resource_id = payload_value(event, :resource_id) || subject_id(event)
    interval_kind = link_rf_interval_kind(observable_id)

    %EffectiveInterval{
      interval_id: "effective_interval:#{interval_kind}:#{event.event_id}",
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      kind: interval_kind,
      subject_kind: :link,
      subject_id: resource_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: event.event_id,
      superseded_by_event_id: next_event && next_event.event_id,
      payload: link_rf_state_payload(event, observable_id, resource_id),
      metadata: %{
        "source_record_kind" => causality_value(event, :source_record_kind),
        "source_record_id" => causality_value(event, :source_record_id),
        "replay_run_id" => causality_value(event, :replay_run_id),
        "event_kind" => event.kind
      }
    }
  end

  defp link_rf_state_payload(%Event{} = event, observable_id, resource_id) do
    state = payload_value(event, :state)

    %{
      "observable_id" => observable_id,
      "resource_id" => resource_id,
      "scope_kind" => payload_value(event, :scope_kind),
      "transport_id" => payload_value(event, :transport_id),
      "source_endpoint_id" => payload_value(event, :source_endpoint_id),
      "ground_station_id" => payload_value(event, :ground_station_id),
      "link_id" => payload_value(event, :link_id),
      "adapter_key" => payload_value(event, :adapter_key),
      "rf_state_family" => link_rf_state_family(observable_id),
      "rf_lock_state" => rf_lock_state(observable_id, state),
      "frame_sync_state" => frame_sync_state(observable_id, state),
      "state" => state,
      "normalized_state" => payload_value(event, :normalized_state),
      "observed_at" => payload_value(event, :observed_at),
      "replay_run_id" =>
        causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id)
    }
  end

  defp link_rf_interval_kind("link.rf_lock_state"), do: :link_rf_lock_state
  defp link_rf_interval_kind("link.frame_sync_state"), do: :link_frame_sync_state

  defp link_rf_state_family("link.rf_lock_state"), do: :rf_lock
  defp link_rf_state_family("link.frame_sync_state"), do: :frame_sync

  defp rf_lock_state("link.rf_lock_state", state), do: state
  defp rf_lock_state(_observable_id, _state), do: nil

  defp frame_sync_state("link.frame_sync_state", state), do: state
  defp frame_sync_state(_observable_id, _state), do: nil

  defp operational_observable_metric_sample(%Event{} = event) do
    %{
      observable_id: payload_value(event, :observable_id),
      mission_id: event.mission_id,
      organization_id: event.organization_id,
      resource_id: payload_value(event, :resource_id) || subject_id(event),
      scope_kind: payload_value(event, :scope_kind),
      transport_id: payload_value(event, :transport_id),
      spacecraft_id: payload_value(event, :spacecraft_id),
      contact_id: payload_value(event, :contact_id),
      scheduled_contact_id: payload_value(event, :scheduled_contact_id),
      realized_contact_id: payload_value(event, :realized_contact_id),
      source_endpoint_id: payload_value(event, :source_endpoint_id),
      ground_station_id: payload_value(event, :ground_station_id),
      link_id: payload_value(event, :link_id),
      link_assignment_id: payload_value(event, :link_id),
      adapter_key: payload_value(event, :adapter_key),
      value: payload_value(event, :value),
      unit: payload_value(event, :unit),
      downlink_bitrate: payload_value(event, :downlink_bitrate),
      downlink_bitrate_bps: payload_value(event, :downlink_bitrate_bps),
      uplink_bitrate: payload_value(event, :uplink_bitrate),
      uplink_bitrate_bps: payload_value(event, :uplink_bitrate_bps),
      bitrate: payload_value(event, :bitrate),
      snr_db: payload_value(event, :snr_db),
      snr: payload_value(event, :snr),
      signal_to_noise_ratio_db: payload_value(event, :signal_to_noise_ratio_db),
      eb_n0_db: payload_value(event, :eb_n0_db),
      ebn0_db: payload_value(event, :ebn0_db),
      energy_per_bit_to_noise_density_db:
        payload_value(event, :energy_per_bit_to_noise_density_db),
      symbol_rate_sps: payload_value(event, :symbol_rate_sps),
      symbol_rate: payload_value(event, :symbol_rate),
      symbols_per_second: payload_value(event, :symbols_per_second),
      doppler_hz: payload_value(event, :doppler_hz),
      doppler: payload_value(event, :doppler),
      frequency_offset_hz: payload_value(event, :frequency_offset_hz),
      carrier_frequency_offset_hz: payload_value(event, :carrier_frequency_offset_hz),
      observed_at: payload_datetime_value(event, :observed_at) || event.occurred_at,
      source_event_id: event.event_id,
      replay_run_id:
        causality_value(event, :replay_run_id) || payload_value(event, :replay_run_id)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
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

  defp maybe_filter_sample_payload(samples, _key, nil), do: samples

  defp maybe_filter_sample_payload(samples, key, values) when is_list(values) do
    normalized_values = Enum.map(values, &normalize_filter_value/1)

    Enum.filter(samples, fn sample ->
      normalized_sample_value =
        sample
        |> map_value(key)
        |> normalize_payload_filter_value()

      normalized_sample_value in normalized_values
    end)
  end

  defp maybe_filter_sample_payload(samples, key, value) do
    normalized_value = normalize_filter_value(value)

    Enum.filter(samples, fn sample ->
      sample
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

  defp order_samples(samples, order) when order in [:desc, "desc"] do
    Enum.sort_by(samples, &sample_sort_key/1, :desc)
  end

  defp order_samples(samples, _order) do
    Enum.sort_by(samples, &sample_sort_key/1, :asc)
  end

  defp sample_sort_key(sample) do
    observed_at = sample_datetime_value(sample, :observed_at)
    source_event_id = map_value(sample, :source_event_id) || ""

    {DateTime.to_unix(observed_at, :microsecond), source_event_id}
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

  defp payload_datetime_value(%Event{payload: payload}, key),
    do: datetime_value(map_value(payload, key))

  defp current_value(%Event{current: current}, key), do: map_value(current, key)
  defp causality_value(%Event{causality: causality}, key), do: map_value(causality, key)

  defp subject_id(%Event{subject: %{id: id}}), do: id
  defp subject_id(%Event{subject: %{"id" => id}}), do: id
  defp subject_id(%Event{}), do: nil

  defp source_binding_id(%Event{} = event),
    do: payload_value(event, :binding_id) || subject_id(event)

  defp transport_capability_id(%Event{} = event),
    do: payload_value(event, :capability_instance_id) || subject_id(event)

  defp operational_observable_state_key(%Event{} = event) do
    {
      payload_value(event, :observable_id),
      payload_value(event, :resource_id) || subject_id(event)
    }
  end

  defp catalog_database_id(%Event{} = event), do: payload_value(event, :catalog_database_id)

  defp subject_kind(%Event{subject: %{kind: kind}}), do: kind
  defp subject_kind(%Event{subject: %{"kind" => kind}}), do: kind
  defp subject_kind(%Event{}), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp sample_datetime_value(sample, key), do: datetime_value(map_value(sample, key))

  defp datetime_value(%DateTime{} = datetime), do: datetime

  defp datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp datetime_value(_value), do: nil

  defp normalize_payload_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_payload_filter_value(value), do: value
end
