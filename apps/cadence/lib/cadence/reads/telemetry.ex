defmodule Cadence.Reads.Telemetry do
  @moduledoc """
  Read-side queries over live current values and optional telemetry history.
  """

  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Sample}
  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  def observation_identity_states(identity_ids, opts) do
    TelemetryStorage.fetch_observation_identity_states(identity_ids, opts)
  end

  def fetch_observation_identity_decision_event(decision_event_id, opts) do
    TelemetryStorage.fetch_observation_identity_decision_event(decision_event_id, opts)
  end

  def list_backfill_lifecycle_events(mission_id, opts) do
    TelemetryStorage.list_backfill_lifecycle_events(mission_id, opts)
  end

  def fetch_backfill_lifecycle_event(backfill_lifecycle_event_id, opts) do
    TelemetryStorage.fetch_backfill_lifecycle_event(backfill_lifecycle_event_id, opts)
  end

  @spec latest_value(binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    cond do
      replay_run_id?(opts) ->
        mission_id
        |> HistoryStore.sample_history(point_id, latest_as_of_opts(opts))
        |> List.first()

      match?(%DateTime{}, Keyword.get(opts, :to_receipt_time)) ->
        mission_id
        |> HistoryStore.sample_history(point_id, latest_as_of_opts(opts))
        |> List.first()

      true ->
        CurrentValueStore.latest_value(mission_id, point_id, opts)
    end
  end

  @spec latest_value(binary(), binary(), binary(), keyword()) :: Sample.t() | nil
  def latest_value(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    cond do
      replay_run_id?(opts) ->
        organization_id
        |> HistoryStore.sample_history(mission_id, point_id, latest_as_of_opts(opts))
        |> List.first()

      match?(%DateTime{}, Keyword.get(opts, :to_receipt_time)) ->
        organization_id
        |> HistoryStore.sample_history(mission_id, point_id, latest_as_of_opts(opts))
        |> List.first()

      true ->
        CurrentValueStore.latest_value(organization_id, mission_id, point_id, opts)
    end
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

  @spec sample_history_result(binary(), binary(), keyword()) ::
          {:ok, %{samples: [Sample.t()], diagnostics: map()}} | {:error, term()}
  def sample_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    HistoryStore.sample_history_result(mission_id, point_id, opts)
  end

  @spec sample_history_result(binary(), binary(), binary(), keyword()) ::
          {:ok, %{samples: [Sample.t()], diagnostics: map()}} | {:error, term()}
  def sample_history_result(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    HistoryStore.sample_history_result(organization_id, mission_id, point_id, opts)
  end

  @spec decimated_sample_history(binary(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def decimated_sample_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    HistoryStore.decimated_sample_history(mission_id, point_id, opts)
  end

  @spec decimated_sample_history(binary(), binary(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def decimated_sample_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    HistoryStore.decimated_sample_history(organization_id, mission_id, point_id, opts)
  end

  @spec decimated_sample_history_result(binary(), binary(), keyword()) ::
          {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  def decimated_sample_history_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    HistoryStore.decimated_sample_history_result(mission_id, point_id, opts)
  end

  @spec decimated_sample_history_result(binary(), binary(), binary(), keyword()) ::
          {:ok, %{buckets: [map()], diagnostics: map()}} | {:error, term()}
  def decimated_sample_history_result(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    HistoryStore.decimated_sample_history_result(organization_id, mission_id, point_id, opts)
  end

  @spec sample_watermark(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def sample_watermark(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    HistoryStore.sample_watermark_result(mission_id, point_id, opts)
  end

  @spec sample_watermark(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def sample_watermark(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    HistoryStore.sample_watermark_result(organization_id, mission_id, point_id, opts)
  end

  defp latest_as_of_opts(opts) do
    opts
    |> Keyword.put(:order, :desc)
    |> Keyword.put(:limit, 1)
  end

  defp replay_run_id?(opts) do
    case Keyword.get(opts, :replay_run_id) do
      value when is_binary(value) -> String.trim(value) != ""
      _value -> false
    end
  end
end
