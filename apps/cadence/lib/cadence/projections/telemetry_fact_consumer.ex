defmodule Cadence.Projections.TelemetryFactConsumer do
  @moduledoc "Projection consumer for committed data-plane telemetry facts."

  use GenServer

  require Logger

  alias Cadence.Projections.TelemetryLatestValues
  alias Cadence.Telemetry.{Facts, ObservationIdentitySelectionChanged}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    :ok = Facts.subscribe(self())

    {:ok,
     %{refresh_point: Keyword.get(opts, :refresh_point, &TelemetryLatestValues.refresh_point/3)}}
  end

  @impl true
  def handle_call({:cadence_fact, _topic, fact}, _from, state) do
    {:reply, :ok, consume(fact, state)}
  end

  @impl true
  def handle_cast({:cadence_fact, _topic, fact}, state) do
    {:noreply, consume(fact, state)}
  end

  defp consume(
         %ObservationIdentitySelectionChanged{} = fact,
         %{refresh_point: refresh_point} = state
       ) do
    case refresh_point.(fact.mission_id, fact.point_id, selection_opts(fact)) do
      {:ok, _sample_or_nil} -> :ok
      {:error, reason} -> log_refresh_failure(fact, reason)
    end

    state
  end

  defp consume(_fact, state), do: state

  defp selection_opts(%ObservationIdentitySelectionChanged{} = fact) do
    [
      organization_id: fact.organization_id,
      spacecraft_id: fact.spacecraft_id,
      realm: fact.realm,
      replay_run_id: fact.replay_run_id,
      data_source_id: fact.data_source_id,
      binding_id: fact.binding_id
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  defp log_refresh_failure(fact, reason) do
    Logger.error(
      "telemetry latest-value projection refresh failed for #{fact.observation_identity_id}: #{inspect(reason)}"
    )
  end
end
