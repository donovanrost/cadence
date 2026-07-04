defmodule Cadence.Dashboards.SourceHealth do
  @moduledoc """
  Durable source-health transition log and latest-status projection.

  This is intentionally scoped to dashboard source identities. It records the
  concrete source that dashboard resolution used, not a global operational event
  taxonomy. A later operational event spine can subscribe to or import these
  transition facts without changing the dashboard runtime contract.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Dashboards.{
    DataSource,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    RuntimeCache,
    RuntimeInvalidation,
    SourceHealthEvent,
    SourceHealthStatus
  }

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  alias Cadence.Persistence.Schemas.{
    DashboardSourceHealthEventRow,
    DashboardSourceHealthStatusRow
  }

  alias Cadence.Repo

  @type record_result ::
          {:ok, SourceHealthEvent.t(), SourceHealthStatus.t()}
          | {:ok, :unchanged, SourceHealthStatus.t()}
          | {:error, term()}

  @type freshness :: :fresh | :stale | :missing

  @type classification :: %{
          freshness: freshness(),
          source_health: SourceHealthEvent.source_health(),
          reason: atom() | binary(),
          observed_at: DateTime.t() | nil,
          last_seen_at: DateTime.t() | nil,
          age_ms: integer() | nil,
          max_age_ms: integer() | nil,
          raw_source_health: SourceHealthEvent.source_health() | nil,
          raw_reason: atom() | binary() | nil,
          status: SourceHealthStatus.t() | nil
        }

  @default_max_age_ms 86_400_000

  @spec record_source_health(map(), keyword()) :: record_result()
  def record_source_health(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    seed = SourceHealthEvent.new(attrs)

    Repo.transaction(fn ->
      current_row = Repo.get(DashboardSourceHealthStatusRow, seed.source_health_key)
      current_status = current_row && DashboardSourceHealthStatusRow.to_domain(current_row)

      if same_health?(current_status, seed) do
        touch_status!(current_row, seed)
      else
        record_transition!(attrs, seed, current_status)
      end
    end)
    |> case do
      {:ok, {:changed, event, status}} ->
        maybe_invalidate_source_health(event, opts)
        {:ok, event, status}

      {:ok, {:unchanged, status}} ->
        {:ok, :unchanged, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec maybe_record_source_health(map(), keyword()) :: :ok | {:error, term()}
  def maybe_record_source_health(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    if enabled?(opts) do
      case record_source_health(attrs, opts) do
        {:ok, :unchanged, _status} -> :ok
        {:ok, _event, _status} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  @spec list_source_health_events(binary() | nil, binary() | nil, keyword()) :: [
          SourceHealthEvent.t()
        ]
  def list_source_health_events(organization_id, mission_id, opts \\ []) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    DashboardSourceHealthEventRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> maybe_filter_in(:source_health_key, Keyword.get(opts, :source_health_keys))
    |> maybe_filter(:logical_source, Keyword.get(opts, :logical_source))
    |> maybe_filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> maybe_filter(:source_binding_id, Keyword.get(opts, :source_binding_id))
    |> maybe_filter(:realm, Keyword.get(opts, :realm))
    |> maybe_filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> maybe_filter(:dataset, Keyword.get(opts, :dataset))
    |> maybe_filter(:source_health, Keyword.get(opts, :source_health))
    |> maybe_from_observed_at(Keyword.get(opts, :from_observed_at))
    |> maybe_to_observed_at(Keyword.get(opts, :to_observed_at))
    |> order_source_health_events(Keyword.get(opts, :order, :desc))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&DashboardSourceHealthEventRow.to_domain/1)
  end

  @spec list_source_health_statuses(binary() | nil, binary() | nil, keyword()) :: [
          SourceHealthStatus.t()
        ]
  def list_source_health_statuses(organization_id, mission_id, opts \\ []) when is_list(opts) do
    DashboardSourceHealthStatusRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> maybe_filter(:logical_source, Keyword.get(opts, :logical_source))
    |> maybe_filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> maybe_filter(:source_binding_id, Keyword.get(opts, :source_binding_id))
    |> maybe_filter(:realm, Keyword.get(opts, :realm))
    |> maybe_filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> maybe_filter(:dataset, Keyword.get(opts, :dataset))
    |> maybe_filter(:source_health, Keyword.get(opts, :source_health))
    |> order_by([row], asc: row.logical_source, asc: row.data_source_id, asc: row.realm)
    |> Repo.all()
    |> Enum.map(&DashboardSourceHealthStatusRow.to_domain/1)
  end

  @spec fetch_source_health_status(binary()) ::
          {:ok, SourceHealthStatus.t()} | {:error, :source_health_status_not_found}
  def fetch_source_health_status(source_health_key) when is_binary(source_health_key) do
    case Repo.get(DashboardSourceHealthStatusRow, source_health_key) do
      nil -> {:error, :source_health_status_not_found}
      row -> {:ok, DashboardSourceHealthStatusRow.to_domain(row)}
    end
  end

  @spec fetch_status_for_source(PlannedSourceRequest.t(), ResolvedSourceBinding.t()) ::
          {:ok, SourceHealthStatus.t()} | {:error, :source_health_status_not_found}
  def fetch_status_for_source(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding
      ) do
    identity = source_identity(request, resolved_binding)
    exact_key = SourceHealthEvent.source_health_key(identity)

    source_key =
      identity
      |> Map.merge(%{source_binding_id: nil, realm: nil, replay_run_id: nil, dataset: nil})
      |> SourceHealthEvent.source_health_key()

    case fetch_source_health_status(exact_key) do
      {:ok, status} -> {:ok, status}
      {:error, :source_health_status_not_found} -> fetch_source_health_status(source_key)
    end
  end

  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts \\ []) when is_list(opts) do
    case Keyword.fetch(opts, :source_health_events?) do
      {:ok, enabled?} -> enabled?
      :error -> dashboard_source_health_events_enabled?()
    end
  end

  @spec classify_status(SourceHealthStatus.t() | nil, DataSource.t() | nil, keyword()) ::
          classification()
  def classify_status(status, data_source \\ nil, opts \\ [])

  def classify_status(nil, data_source, opts) when is_list(opts) do
    %{
      freshness: :missing,
      source_health: :unknown,
      reason: :source_health_missing,
      observed_at: nil,
      last_seen_at: nil,
      age_ms: nil,
      max_age_ms: max_age_ms(data_source, opts),
      raw_source_health: nil,
      raw_reason: nil,
      status: nil
    }
  end

  def classify_status(%SourceHealthStatus{} = status, data_source, opts) when is_list(opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0) |> DateTime.truncate(:microsecond)
    last_seen_at = status.last_seen_at || status.observed_at
    age_ms = last_seen_at && DateTime.diff(now, last_seen_at, :millisecond)
    max_age_ms = max_age_ms(data_source, opts)

    if stale?(age_ms, max_age_ms) do
      %{
        freshness: :stale,
        source_health: :unknown,
        reason: :source_health_stale,
        observed_at: status.observed_at,
        last_seen_at: last_seen_at,
        age_ms: age_ms,
        max_age_ms: max_age_ms,
        raw_source_health: status.source_health,
        raw_reason: status.reason,
        status: status
      }
    else
      %{
        freshness: :fresh,
        source_health: status.source_health,
        reason: status.reason,
        observed_at: status.observed_at,
        last_seen_at: last_seen_at,
        age_ms: age_ms,
        max_age_ms: max_age_ms,
        raw_source_health: status.source_health,
        raw_reason: status.reason,
        status: status
      }
    end
  end

  defp same_health?(%SourceHealthStatus{} = status, %SourceHealthEvent{} = event),
    do: status.source_health == event.source_health

  defp same_health?(_status, _event), do: false

  defp touch_status!(%DashboardSourceHealthStatusRow{} = row, %SourceHealthEvent{} = event) do
    case Repo.update(
           DashboardSourceHealthStatusRow.touch_changeset(row, event.observed_at, event.payload)
         ) do
      {:ok, row} ->
        {:unchanged, DashboardSourceHealthStatusRow.to_domain(row)}

      {:error, %Changeset{} = changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp record_transition!(attrs, %SourceHealthEvent{} = seed, current_status) do
    previous_source_health = current_status && current_status.source_health

    event =
      attrs
      |> Map.merge(%{
        source_health_key: seed.source_health_key,
        previous_source_health: previous_source_health
      })
      |> SourceHealthEvent.new()

    with {:ok, event_row} <- Repo.insert(DashboardSourceHealthEventRow.changeset(event)),
         source_health_event <- DashboardSourceHealthEventRow.to_domain(event_row),
         {:ok, %OperationalEvent{}} <-
           persist_source_health_operational_event(source_health_event),
         {:ok, status_row} <-
           source_health_event
           |> SourceHealthStatus.from_event(next_transition_count(current_status))
           |> DashboardSourceHealthStatusRow.changeset()
           |> Repo.insert(
             on_conflict: {:replace, DashboardSourceHealthStatusRow.upsert_fields()},
             conflict_target: :source_health_key
           ) do
      {:changed, source_health_event, DashboardSourceHealthStatusRow.to_domain(status_row)}
    else
      {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_source_health_operational_event(%SourceHealthEvent{} = event) do
    event
    |> OperationalEvent.from_source_health_event()
    |> then(&OperationalEvents.persist_event(Repo, &1))
  end

  defp next_transition_count(nil), do: 1
  defp next_transition_count(%SourceHealthStatus{transition_count: count}), do: count + 1

  defp maybe_invalidate_source_health(%SourceHealthEvent{} = event, opts) do
    if Keyword.get(opts, :invalidate_runtime_cache?, true) do
      RuntimeInvalidation.source_health_changed(
        %{
          organization_id: event.organization_id,
          mission_id: event.mission_id,
          logical_source: event.logical_source,
          data_source_id: event.data_source_id,
          source_binding_id: event.source_binding_id,
          realm: event.realm,
          replay_run_id: event.replay_run_id,
          dataset: event.dataset,
          source_health: event.source_health,
          previous_source_health: event.previous_source_health,
          reason: event.reason,
          observed_at: event.observed_at,
          evidence_ref: %{kind: "dashboard_source_health_event", id: event.source_health_event_id}
        },
        runtime_cache: Keyword.get(opts, :runtime_cache, RuntimeCache)
      )
    end

    :ok
  end

  defp source_identity(%PlannedSourceRequest{} = request, %ResolvedSourceBinding{} = binding) do
    %{
      organization_id:
        request.organization_id || binding.binding.organization_id ||
          binding.data_source.organization_id,
      mission_id:
        request.mission_id || binding.binding.mission_id || binding.data_source.mission_id,
      logical_source: request.logical_source || binding.binding.logical_source,
      data_source_id: binding.data_source.data_source_id,
      source_binding_id: binding.binding.binding_id,
      realm: binding.realm,
      replay_run_id: requested_replay_run_id(request),
      dataset: binding.dataset
    }
  end

  defp requested_replay_run_id(%PlannedSourceRequest{} = request) do
    get_attr(request.data_context, :replay_run_id) ||
      get_attr(request.time_context, :replay_run_id)
  end

  defp maybe_scope_organization(query, nil), do: query

  defp maybe_scope_organization(query, organization_id) when is_binary(organization_id) do
    where(query, [row], is_nil(row.organization_id) or row.organization_id == ^organization_id)
  end

  defp maybe_scope_mission(query, nil), do: query

  defp maybe_scope_mission(query, mission_id) when is_binary(mission_id) do
    where(query, [row], row.mission_id == ^mission_id)
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    value = enum_string(value)
    where(query, [row], field(row, ^field) == ^value)
  end

  defp maybe_filter_in(query, _field, nil), do: query
  defp maybe_filter_in(query, _field, []), do: where(query, [_row], false)

  defp maybe_filter_in(query, field, values) when is_list(values) do
    values = Enum.map(values, &enum_string/1)
    where(query, [row], field(row, ^field) in ^values)
  end

  defp maybe_from_observed_at(query, nil), do: query

  defp maybe_from_observed_at(query, %DateTime{} = from_observed_at) do
    where(query, [row], row.observed_at >= ^from_observed_at)
  end

  defp maybe_to_observed_at(query, nil), do: query

  defp maybe_to_observed_at(query, %DateTime{} = to_observed_at) do
    where(query, [row], row.observed_at < ^to_observed_at)
  end

  defp order_source_health_events(query, order) when order in [:asc, "asc"] do
    order_by(query, [row], asc: row.observed_at, asc: row.inserted_at)
  end

  defp order_source_health_events(query, _order) do
    order_by(query, [row], desc: row.observed_at, desc: row.inserted_at)
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp get_attr(attrs, key) when is_list(attrs) and is_atom(key) do
    attrs
    |> Map.new()
    |> get_attr(key)
  end

  defp get_attr(_attrs, _key), do: nil

  defp dashboard_source_health_events_enabled? do
    :cadence
    |> Application.get_env(:dashboard_source_health_events, [])
    |> Keyword.get(:enabled?, true)
  end

  defp stale?(age_ms, max_age_ms)
       when is_integer(age_ms) and is_integer(max_age_ms) and max_age_ms >= 0 do
    age_ms > max_age_ms
  end

  defp stale?(_age_ms, _max_age_ms), do: false

  defp max_age_ms(data_source, opts) do
    policy = source_health_freshness_policy(opts)
    kind = data_source && normalize_policy_key(data_source.kind)
    storage = data_source && normalize_policy_key(metadata_value(data_source.metadata, :storage))

    first_integer([
      get_nested_attr(policy, [kind, storage]),
      get_nested_attr(policy, [kind, :default_max_age_ms]),
      get_attr(policy, :default_max_age_ms),
      @default_max_age_ms
    ])
  end

  defp source_health_freshness_policy(opts) do
    case Keyword.fetch(opts, :source_health_freshness) do
      {:ok, policy} ->
        policy

      :error ->
        :cadence
        |> Application.get_env(:dashboard_source_health_events, [])
        |> Keyword.get(:freshness, [])
    end
  end

  defp get_nested_attr(_attrs, [nil | _rest]), do: nil
  defp get_nested_attr(attrs, [key]), do: get_attr(attrs, key)

  defp get_nested_attr(attrs, [key | rest]) do
    attrs
    |> get_attr(key)
    |> get_nested_attr(rest)
  end

  defp first_integer(values) do
    Enum.find_value(values, fn
      value when is_integer(value) and value >= 0 -> value
      _other -> nil
    end)
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp normalize_policy_key(nil), do: nil
  defp normalize_policy_key(value) when is_atom(value), do: value

  defp normalize_policy_key(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp normalize_policy_key(_value), do: nil
end
