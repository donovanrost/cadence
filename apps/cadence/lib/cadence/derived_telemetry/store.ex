defmodule Cadence.DerivedTelemetry.Store do
  @moduledoc "Data-plane persistence boundary for derived telemetry samples and latest values."

  import Ecto.Query

  alias Cadence.DerivedTelemetry.Sample
  alias Cadence.DerivedTelemetry.Store.{LatestValueRow, SampleRow}
  alias Cadence.Repo
  alias Cadence.Telemetry.LatestProjectionOrder
  alias Ecto.Multi

  @mission_scope_key "__mission__"

  @spec add_sample_inserts(Multi.t(), [Sample.t()]) :: Multi.t()
  def add_sample_inserts(%Multi{} = multi, samples) when is_list(samples) do
    Enum.reduce(samples, multi, fn %Sample{} = sample, acc ->
      Multi.insert(
        acc,
        {:derived_sample, sample.derived_sample_id},
        SampleRow.changeset(sample),
        on_conflict: :nothing,
        conflict_target: [:derived_sample_id]
      )
    end)
  end

  @spec persist_latest_values(module(), [Sample.t()]) :: {:ok, [struct()]} | {:error, term()}
  def persist_latest_values(repo, samples) when is_list(samples) do
    Enum.reduce_while(samples, {:ok, []}, fn %Sample{} = sample, {:ok, acc} ->
      case persist_latest_value(repo, sample) do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec list_samples(binary(), keyword()) :: [Sample.t()]
  def list_samples(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    SampleRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter(:organization_id, Keyword.get(opts, :organization_id))
    |> maybe_filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> maybe_filter(:point_id, Keyword.get(opts, :point_id))
    |> order_samples(Keyword.get(opts, :order, :desc))
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> Enum.map(&SampleRow.to_domain/1)
  end

  @spec latest_value(binary() | nil, binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(organization_id, mission_id, point_id, opts)
      when (is_nil(organization_id) or is_binary(organization_id)) and is_binary(mission_id) and
             is_binary(point_id) and is_list(opts) do
    scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    LatestValueRow
    |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
    |> maybe_filter(:organization_id, organization_id)
    |> maybe_filter_latest_spacecraft(scope_id, opts)
    |> order_by(
      [row],
      desc: row.receipt_time,
      desc: row.generation_time,
      desc: row.derived_sample_id
    )
    |> limit(1)
    |> Repo.one()
    |> case do
      %LatestValueRow{} = row -> LatestValueRow.to_domain(row)
      nil -> nil
    end
  end

  @spec list_latest_values(binary(), keyword()) :: [Sample.t()]
  def list_latest_values(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    LatestValueRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter(:organization_id, Keyword.get(opts, :organization_id))
    |> maybe_filter_latest_spacecraft(scope_id, opts)
    |> order_by([row], asc: row.point_name)
    |> Repo.all()
    |> Enum.map(&LatestValueRow.to_domain/1)
  end

  @spec replace_latest_values(binary(), [Sample.t()], keyword()) :: :ok | {:error, term()}
  def replace_latest_values(mission_id, samples, opts \\ [])
      when is_binary(mission_id) and is_list(samples) and is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    Repo.transaction(fn ->
      LatestValueRow
      |> where([row], row.mission_id == ^mission_id)
      |> maybe_filter_rebuild_spacecraft(spacecraft_id)
      |> Repo.delete_all()

      Enum.each(samples, fn %Sample{} = sample ->
        %LatestValueRow{}
        |> LatestValueRow.changeset(sample)
        |> Repo.insert!()
      end)
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_latest_value(repo, %Sample{} = sample) do
    existing =
      repo.get_by(LatestValueRow,
        mission_id: sample.mission_id,
        spacecraft_scope_id: spacecraft_scope_id(sample.spacecraft_id),
        point_id: sample.point_id
      )

    cond do
      is_nil(existing) ->
        %LatestValueRow{} |> LatestValueRow.changeset(sample) |> repo.insert()

      LatestProjectionOrder.newer?(sample, existing, :derived_sample_id) ->
        existing |> LatestValueRow.changeset(sample) |> repo.update()

      true ->
        {:ok, existing}
    end
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [row], field(row, ^field) == ^value)

  defp maybe_filter_latest_spacecraft(query, scope_id, opts) do
    if Keyword.has_key?(opts, :spacecraft_id) do
      where(query, [row], row.spacecraft_scope_id == ^scope_id)
    else
      query
    end
  end

  defp maybe_filter_rebuild_spacecraft(query, nil), do: query

  defp maybe_filter_rebuild_spacecraft(query, spacecraft_id),
    do: where(query, [row], row.spacecraft_scope_id == ^spacecraft_id)

  defp order_samples(query, :asc),
    do: order_by(query, [row], asc: row.receipt_time, asc: row.derived_sample_id)

  defp order_samples(query, _order),
    do: order_by(query, [row], desc: row.receipt_time, desc: row.derived_sample_id)

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id
end
