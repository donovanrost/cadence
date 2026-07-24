defmodule Cadence.TestSupport.LazyCurrentValueStore do
  @moduledoc false

  @behaviour Cadence.Telemetry.CurrentValueStore

  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
  end

  def start_link(_opts), do: Agent.start_link(fn -> [] end)

  def hot_path_safe?, do: true

  def record_samples(_samples), do: :ok

  def replace_value(_mission_id, _point_id, _sample_or_nil, _opts), do: :ok

  def replace_values_for_scope(_mission_id, _samples, _opts), do: :ok

  def latest_value(_mission_id, _point_id, _opts), do: nil

  def latest_values_for_mission(_mission_id, _opts), do: []

  def reset, do: :ok

  def reset(_mission_id), do: :ok
end
