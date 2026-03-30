defmodule Cadence.Reads.DerivedTelemetry do
  @moduledoc """
  Read-side queries for canonical derived telemetry samples.
  """

  import Ecto.Query

  alias Cadence.DerivedTelemetry.Sample

  alias Cadence.Persistence.Schemas.{
    DerivedTelemetryLatestValueRow,
    DerivedTelemetrySampleRow
  }

  alias Cadence.Repo

  @mission_scope_key "__mission__"

  @spec latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    DerivedTelemetryLatestValueRow
    |> where(
      [latest_value_row],
      latest_value_row.mission_id == ^mission_id and latest_value_row.point_id == ^point_id
    )
    |> maybe_filter_latest_spacecraft(spacecraft_scope_id, opts)
    |> order_by(
      [latest_value_row],
      desc: latest_value_row.receipt_time,
      desc: latest_value_row.generation_time,
      desc: latest_value_row.derived_sample_id
    )
    |> limit(1)
    |> Repo.one()
    |> maybe_to_sample()
  end

  @spec latest_value(binary(), binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    DerivedTelemetryLatestValueRow
    |> where(
      [latest_value_row],
      latest_value_row.organization_id == ^organization_id and
        latest_value_row.mission_id == ^mission_id and latest_value_row.point_id == ^point_id
    )
    |> maybe_filter_latest_spacecraft(spacecraft_scope_id, opts)
    |> order_by(
      [latest_value_row],
      desc: latest_value_row.receipt_time,
      desc: latest_value_row.generation_time,
      desc: latest_value_row.derived_sample_id
    )
    |> limit(1)
    |> Repo.one()
    |> maybe_to_sample()
  end

  @spec latest_values_for_mission(binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    DerivedTelemetryLatestValueRow
    |> where([latest_value_row], latest_value_row.mission_id == ^mission_id)
    |> maybe_filter_latest_spacecraft(spacecraft_scope_id, opts)
    |> order_by([latest_value_row], asc: latest_value_row.point_name)
    |> Repo.all()
    |> Enum.map(&DerivedTelemetryLatestValueRow.to_domain/1)
  end

  @spec latest_values_for_mission(binary(), binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    DerivedTelemetryLatestValueRow
    |> where(
      [latest_value_row],
      latest_value_row.organization_id == ^organization_id and
        latest_value_row.mission_id == ^mission_id
    )
    |> maybe_filter_latest_spacecraft(spacecraft_scope_id, opts)
    |> order_by([latest_value_row], asc: latest_value_row.point_name)
    |> Repo.all()
    |> Enum.map(&DerivedTelemetryLatestValueRow.to_domain/1)
  end

  @spec sample_history(binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)

    DerivedTelemetrySampleRow
    |> where(
      [sample_row],
      sample_row.mission_id == ^mission_id and sample_row.point_id == ^point_id
    )
    |> maybe_filter_spacecraft(spacecraft_id)
    |> order_history(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&DerivedTelemetrySampleRow.to_domain/1)
  end

  @spec sample_history(binary(), binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)

    DerivedTelemetrySampleRow
    |> where(
      [sample_row],
      sample_row.organization_id == ^organization_id and sample_row.mission_id == ^mission_id and
        sample_row.point_id == ^point_id
    )
    |> maybe_filter_spacecraft(spacecraft_id)
    |> order_history(order)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&DerivedTelemetrySampleRow.to_domain/1)
  end

  defp maybe_filter_spacecraft(query, nil), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id),
    do: where(query, [sample_row], sample_row.spacecraft_id == ^spacecraft_id)

  defp maybe_filter_latest_spacecraft(query, spacecraft_scope_id, opts) do
    if Keyword.has_key?(opts, :spacecraft_id) do
      where(
        query,
        [latest_value_row],
        latest_value_row.spacecraft_scope_id == ^spacecraft_scope_id
      )
    else
      query
    end
  end

  defp order_history(query, :asc),
    do:
      order_by(query, [sample_row],
        asc: sample_row.receipt_time,
        asc: sample_row.derived_sample_id
      )

  defp order_history(query, _order),
    do:
      order_by(query, [sample_row],
        desc: sample_row.receipt_time,
        desc: sample_row.derived_sample_id
      )

  defp maybe_to_sample(nil), do: nil

  defp maybe_to_sample(%DerivedTelemetryLatestValueRow{} = latest_value_row),
    do: DerivedTelemetryLatestValueRow.to_domain(latest_value_row)

  defp maybe_to_sample(%DerivedTelemetrySampleRow{} = sample_row),
    do: DerivedTelemetrySampleRow.to_domain(sample_row)

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id
end
