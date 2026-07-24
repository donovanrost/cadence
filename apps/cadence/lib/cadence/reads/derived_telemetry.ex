defmodule Cadence.Reads.DerivedTelemetry do
  @moduledoc "Read-side facade for canonical derived telemetry records."

  alias Cadence.DerivedTelemetry.Sample
  alias Cadence.DerivedTelemetry.Store

  @spec latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    Store.latest_value(nil, mission_id, point_id, opts)
  end

  @spec latest_value(binary(), binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    Store.latest_value(organization_id, mission_id, point_id, opts)
  end

  @spec latest_values_for_mission(binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    Store.list_latest_values(mission_id, opts)
  end

  @spec latest_values_for_mission(binary(), binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    Store.list_latest_values(mission_id, Keyword.put(opts, :organization_id, organization_id))
  end

  @spec sample_history(binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    Store.list_samples(mission_id, Keyword.put(opts, :point_id, point_id))
  end

  @spec sample_history(binary(), binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    Store.list_samples(
      mission_id,
      opts
      |> Keyword.put(:point_id, point_id)
      |> Keyword.put(:organization_id, organization_id)
    )
  end
end
