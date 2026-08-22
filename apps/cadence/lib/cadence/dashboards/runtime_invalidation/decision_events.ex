defmodule Cadence.Dashboards.RuntimeInvalidation.DecisionEvents do
  @moduledoc """
  Durable persistence boundary for dashboard runtime invalidation decisions.
  """

  import Ecto.Query

  alias Cadence.Dashboards.RuntimeInvalidation.DecisionEvent
  alias Cadence.Dashboards.RuntimeInvalidation.DecisionEvents.DecisionEventRow
  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias Cadence.Repo

  @filter_keys [
    :organization_id,
    :mission_id,
    :dashboard_id,
    :decision_status,
    :boundary,
    :context_reason,
    :refresh_reason,
    :refresh_allowed?
  ]

  @spec record(Event.t(), map(), keyword()) ::
          {:ok, DecisionEvent.t()} | {:error, Ecto.Changeset.t()}
  def record(%Event{} = event, decision, opts \\ []) when is_map(decision) and is_list(opts) do
    event
    |> DecisionEvent.new(decision, opts)
    |> DecisionEventRow.changeset()
    |> Repo.insert()
    |> case do
      {:ok, row} -> {:ok, DecisionEventRow.to_domain(row)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec list(keyword()) :: [DecisionEvent.t()]
  def list(opts \\ []) when is_list(opts) do
    DecisionEventRow
    |> apply_filters(opts)
    |> maybe_replay_run_id(Keyword.get(opts, :replay_run_id))
    |> maybe_affected_placement_id(Keyword.get(opts, :affected_placement_id))
    |> maybe_decision_event_id(
      Keyword.get(opts, :dashboard_runtime_invalidation_decision_event_id)
    )
    |> maybe_decision_event_id(Keyword.get(opts, :decision_event_id))
    |> maybe_invalidation_event_id(Keyword.get(opts, :invalidation_event_id))
    |> maybe_from_observed_at(Keyword.get(opts, :from_decision_observed_at))
    |> maybe_to_observed_at(Keyword.get(opts, :to_decision_observed_at))
    |> order_by([row], desc: row.decision_observed_at, desc: row.inserted_at)
    |> limit(^result_limit(opts))
    |> Repo.all()
    |> Enum.map(&DecisionEventRow.to_domain/1)
  end

  @spec list_decision_rows(keyword()) :: [map()]
  def list_decision_rows(opts \\ []) when is_list(opts) do
    opts
    |> list()
    |> Enum.map(&DecisionEvent.to_decision_row/1)
  end

  defp apply_filters(query, opts) do
    Enum.reduce(@filter_keys, query, fn key, query ->
      filter(query, key, Keyword.get(opts, key))
    end)
  end

  defp filter(query, _field, nil), do: query

  defp filter(query, :refresh_allowed?, value) do
    where(query, [row], row.refresh_allowed? == ^value)
  end

  defp filter(query, field, value) do
    normalized_value = enum_string(value)
    where(query, [row], field(row, ^field) == ^normalized_value)
  end

  defp maybe_invalidation_event_id(query, value) when is_binary(value) and value != "" do
    where(query, [row], row.invalidation_event_id == ^value)
  end

  defp maybe_invalidation_event_id(query, _value), do: query

  defp maybe_affected_placement_id(query, value) when is_binary(value) and value != "" do
    where(query, [row], fragment("? = ANY(?)", ^value, row.affected_placement_ids))
  end

  defp maybe_affected_placement_id(query, _value), do: query

  defp maybe_decision_event_id(query, value) when is_binary(value) and value != "" do
    where(query, [row], row.dashboard_runtime_invalidation_decision_event_id == ^value)
  end

  defp maybe_decision_event_id(query, _value), do: query

  defp maybe_replay_run_id(query, value) when is_binary(value) and value != "" do
    where(query, [row], fragment("?->'value'->>'replay_run_id' = ?", row.filters, ^value))
  end

  defp maybe_replay_run_id(query, _value), do: query

  defp maybe_from_observed_at(query, %DateTime{} = observed_at) do
    where(query, [row], row.decision_observed_at >= ^observed_at)
  end

  defp maybe_from_observed_at(query, _observed_at), do: query

  defp maybe_to_observed_at(query, %DateTime{} = observed_at) do
    where(query, [row], row.decision_observed_at < ^observed_at)
  end

  defp maybe_to_observed_at(query, _observed_at), do: query

  defp result_limit(opts) do
    opts
    |> Keyword.get(:limit, 100)
    |> min(500)
    |> max(1)
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value
end
