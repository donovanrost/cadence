defmodule Cadence.Projections.DataSources.Watermarks do
  @moduledoc """
  Durable source-watermark transition log and latest-status projection.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.DataSources.{Facts, SourceWatermark, SourceWatermarkEvent, SourceWatermarkStatus}

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Platform.EventBus

  alias Cadence.Projections.DataSources.Watermarks.{EventRow, StatusRow}
  alias Cadence.Repo

  @type record_result ::
          {:ok, SourceWatermarkEvent.t(), SourceWatermarkStatus.t()}
          | {:ok, :unchanged, SourceWatermarkStatus.t()}
          | {:error, term()}

  @spec record_source_watermark(map(), keyword()) :: record_result()
  def record_source_watermark(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    event_bus = Keyword.get(opts, :event_bus, EventBus)
    seed = SourceWatermarkEvent.new(attrs)

    Repo.transaction(fn ->
      current_row = Repo.get(StatusRow, seed.source_watermark_key)
      current_status = current_row && StatusRow.to_domain(current_row)

      if same_watermark?(current_status, seed) do
        touch_status!(current_row, seed)
      else
        record_transition!(attrs, seed, current_status)
      end
    end)
    |> case do
      {:ok, {:changed, event, status}} ->
        maybe_publish_fact(event_bus, event, opts)
        {:ok, event, status}

      {:ok, {:unchanged, status}} ->
        {:ok, :unchanged, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec maybe_record_source_watermark(map(), keyword()) :: :ok | {:error, term()}
  def maybe_record_source_watermark(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    if enabled?(opts) do
      case record_source_watermark(attrs, opts) do
        {:ok, :unchanged, _status} -> :ok
        {:ok, _event, _status} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  @spec list_source_watermark_events(binary() | nil, binary() | nil, keyword()) :: [
          SourceWatermarkEvent.t()
        ]
  def list_source_watermark_events(organization_id, mission_id, opts \\ []) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    EventRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> maybe_filter(:logical_source, Keyword.get(opts, :logical_source))
    |> maybe_filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> maybe_filter(:source_binding_id, Keyword.get(opts, :source_binding_id))
    |> maybe_filter(:realm, Keyword.get(opts, :realm))
    |> maybe_filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> maybe_filter(:dataset, Keyword.get(opts, :dataset))
    |> maybe_from_observed_at(Keyword.get(opts, :from_observed_at))
    |> maybe_to_observed_at(Keyword.get(opts, :to_observed_at))
    |> order_by([row], desc: row.observed_at, desc: row.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&EventRow.to_domain/1)
  end

  @spec list_source_watermark_statuses(binary() | nil, binary() | nil, keyword()) :: [
          SourceWatermarkStatus.t()
        ]
  def list_source_watermark_statuses(organization_id, mission_id, opts \\ [])
      when is_list(opts) do
    StatusRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> maybe_filter(:logical_source, Keyword.get(opts, :logical_source))
    |> maybe_filter(:data_source_id, Keyword.get(opts, :data_source_id))
    |> maybe_filter(:source_binding_id, Keyword.get(opts, :source_binding_id))
    |> maybe_filter(:realm, Keyword.get(opts, :realm))
    |> maybe_filter(:replay_run_id, Keyword.get(opts, :replay_run_id))
    |> maybe_filter(:dataset, Keyword.get(opts, :dataset))
    |> order_by([row], asc: row.logical_source, asc: row.data_source_id, asc: row.realm)
    |> Repo.all()
    |> Enum.map(&StatusRow.to_domain/1)
  end

  @spec fetch_source_watermark_status(binary()) ::
          {:ok, SourceWatermarkStatus.t()} | {:error, :source_watermark_status_not_found}
  def fetch_source_watermark_status(source_watermark_key) when is_binary(source_watermark_key) do
    case Repo.get(StatusRow, source_watermark_key) do
      nil -> {:error, :source_watermark_status_not_found}
      row -> {:ok, StatusRow.to_domain(row)}
    end
  end

  @spec fetch_status_for_identity(map()) ::
          {:ok, SourceWatermarkStatus.t()} | {:error, :source_watermark_status_not_found}
  def fetch_status_for_identity(identity) when is_map(identity) do
    exact_key = SourceWatermarkEvent.source_watermark_key(identity)

    source_key =
      identity
      |> Map.merge(%{source_binding_id: nil, realm: nil, replay_run_id: nil, dataset: nil})
      |> SourceWatermarkEvent.source_watermark_key()

    case fetch_source_watermark_status(exact_key) do
      {:ok, status} -> {:ok, status}
      {:error, :source_watermark_status_not_found} -> fetch_source_watermark_status(source_key)
    end
  end

  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts \\ []) when is_list(opts) do
    case Keyword.fetch(opts, :source_watermark_events?) do
      {:ok, enabled?} -> enabled?
      :error -> data_source_watermark_events_enabled?()
    end
  end

  @spec attrs_from_source_watermark(SourceWatermark.t(), map(), keyword()) :: map()
  def attrs_from_source_watermark(%SourceWatermark{} = watermark, identity, opts \\ [])
      when is_map(identity) and is_list(opts) do
    %{
      organization_id: get_attr(identity, :organization_id),
      mission_id: get_attr(identity, :mission_id),
      logical_source: watermark.logical_source || get_attr(identity, :logical_source),
      data_source_id: watermark.data_source_id || get_attr(identity, :data_source_id),
      source_binding_id: watermark.source_binding_id || get_attr(identity, :source_binding_id),
      realm: watermark.realm || get_attr(identity, :realm),
      replay_run_id: watermark.replay_run_id || get_attr(identity, :replay_run_id),
      dataset: watermark.dataset || get_attr(identity, :dataset),
      complete_through: watermark.complete_through,
      latest_receipt_time: watermark.latest_receipt_time,
      retention_starts_at: watermark.retention_starts_at,
      sample_count: watermark.sample_count,
      confidence: watermark.confidence,
      reason: Keyword.get(opts, :reason, :source_watermark_observed),
      observed_at: Keyword.get_lazy(opts, :observed_at, &DateTime.utc_now/0),
      payload: Keyword.get(opts, :payload, %{})
    }
  end

  defp same_watermark?(%SourceWatermarkStatus{} = status, %SourceWatermarkEvent{} = event) do
    status.complete_through == event.complete_through and
      status.latest_receipt_time == event.latest_receipt_time and
      effective_retention_starts_at(status, event) == status.retention_starts_at and
      status.sample_count == event.sample_count and
      status.confidence == event.confidence
  end

  defp same_watermark?(_status, _event), do: false

  defp touch_status!(%StatusRow{} = row, %SourceWatermarkEvent{} = event) do
    case Repo.update(
           StatusRow.touch_changeset(
             row,
             event.observed_at,
             event.payload
           )
         ) do
      {:ok, row} ->
        {:unchanged, StatusRow.to_domain(row)}

      {:error, %Changeset{} = changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp record_transition!(attrs, %SourceWatermarkEvent{} = seed, current_status) do
    event =
      attrs
      |> Map.merge(previous_attrs(current_status))
      |> Map.put(:event_type, event_type(seed, current_status))
      |> Map.put(:retention_starts_at, effective_retention_starts_at(current_status, seed))
      |> SourceWatermarkEvent.new()

    with {:ok, event_row} <- Repo.insert(EventRow.changeset(event)),
         source_watermark_event <- EventRow.to_domain(event_row),
         {:ok, %OperationalEvent{}} <-
           persist_source_watermark_operational_event(source_watermark_event),
         {:ok, status_row} <-
           source_watermark_event
           |> SourceWatermarkStatus.from_event(next_transition_count(current_status))
           |> StatusRow.changeset()
           |> Repo.insert(
             on_conflict: {:replace, StatusRow.upsert_fields()},
             conflict_target: :source_watermark_key
           ) do
      {:changed, source_watermark_event, StatusRow.to_domain(status_row)}
    else
      {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_source_watermark_operational_event(%SourceWatermarkEvent{} = event) do
    event
    |> OperationalEvent.from_source_watermark_event()
    |> then(&OperationalEvents.persist_event(Repo, &1))
  end

  defp previous_attrs(nil), do: %{}

  defp previous_attrs(%SourceWatermarkStatus{} = status) do
    %{
      previous_complete_through: status.complete_through,
      previous_latest_receipt_time: status.latest_receipt_time,
      previous_retention_starts_at: status.retention_starts_at
    }
  end

  defp event_type(%SourceWatermarkEvent{}, nil), do: :observed

  defp event_type(%SourceWatermarkEvent{} = event, %SourceWatermarkStatus{} = previous) do
    cond do
      retreated?(event.complete_through, previous.complete_through) or
          retreated?(event.latest_receipt_time, previous.latest_receipt_time) ->
        :retreated

      advanced?(event.complete_through, previous.complete_through) or
          advanced?(event.latest_receipt_time, previous.latest_receipt_time) ->
        :advanced

      true ->
        :changed
    end
  end

  defp advanced?(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right) == :gt

  defp advanced?(%DateTime{}, nil), do: true
  defp advanced?(_left, _right), do: false

  defp retreated?(%DateTime{} = left, %DateTime{} = right),
    do: DateTime.compare(left, right) == :lt

  defp retreated?(nil, %DateTime{}), do: true
  defp retreated?(_left, _right), do: false

  defp effective_retention_starts_at(nil, %SourceWatermarkEvent{} = event),
    do: event.retention_starts_at

  defp effective_retention_starts_at(
         %SourceWatermarkStatus{} = status,
         %SourceWatermarkEvent{} = event
       ) do
    earlier_datetime(status.retention_starts_at, event.retention_starts_at)
  end

  defp earlier_datetime(nil, datetime), do: datetime
  defp earlier_datetime(datetime, nil), do: datetime

  defp earlier_datetime(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.compare(left, right) == :gt, do: right, else: left
  end

  defp next_transition_count(nil), do: 1
  defp next_transition_count(%SourceWatermarkStatus{transition_count: count}), do: count + 1

  defp maybe_publish_fact(event_bus, %SourceWatermarkEvent{} = event, opts) do
    if Keyword.get(opts, :publish_facts?, Keyword.get(opts, :invalidate_runtime_cache?, true)) do
      Facts.publish(event_bus, event)
    end

    :ok
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

  defp maybe_from_observed_at(query, nil), do: query

  defp maybe_from_observed_at(query, %DateTime{} = from_observed_at) do
    where(query, [row], row.observed_at >= ^from_observed_at)
  end

  defp maybe_to_observed_at(query, nil), do: query

  defp maybe_to_observed_at(query, %DateTime{} = to_observed_at) do
    where(query, [row], row.observed_at < ^to_observed_at)
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp data_source_watermark_events_enabled? do
    :cadence
    |> Application.get_env(:data_source_watermark_events, [])
    |> Keyword.get(:enabled?, true)
  end

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil
end
