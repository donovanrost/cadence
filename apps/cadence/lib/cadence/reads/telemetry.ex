defmodule Cadence.Reads.Telemetry do
  @moduledoc """
  Read-side queries over live current values and optional telemetry history.
  """

  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Sample}

  @spec latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    CurrentValueStore.latest_value(mission_id, point_id, opts)
  end

  @spec latest_value(binary(), binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    CurrentValueStore.latest_value(organization_id, mission_id, point_id, opts)
  end

  @spec latest_values_for_mission(binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    CurrentValueStore.latest_values_for_mission(mission_id, opts)
  end

  @spec latest_values_for_mission(binary(), binary(), keyword()) :: [Sample.t()]
  def latest_values_for_mission(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CurrentValueStore.latest_values_for_mission(organization_id, mission_id, opts)
  end

  @spec sample_history(binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    HistoryStore.sample_history(mission_id, point_id, opts)
  end

  @spec sample_history(binary(), binary(), binary(), keyword()) :: [Sample.t()]
  def sample_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    HistoryStore.sample_history(organization_id, mission_id, point_id, opts)
  end
end
