defmodule Cadence.Projections.RuntimeFactConsumer do
  @moduledoc "Projection consumer for committed data-plane runtime facts."

  use GenServer

  alias Cadence.Projections.MissionEvents
  alias Cadence.Repo

  alias Cadence.Runtime.{
    DownlinkRecordsPersisted,
    Facts,
    ManagedRecordsPersisted
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    :ok = Facts.subscribe(self())
    {:ok, %{project_records: Keyword.get(opts, :project_records, &persist_projected_events/1)}}
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
         %ManagedRecordsPersisted{action_requests: action_requests},
         %{project_records: project_records} = state
       ) do
    project_records.(action_requests)
    state
  end

  defp consume(
         %DownlinkRecordsPersisted{
           combined_records: combined_records,
           diagnostics: diagnostics
         },
         %{project_records: project_records} = state
       ) do
    project_records.(combined_records ++ diagnostics)
    state
  end

  defp consume(_fact, state), do: state

  defp persist_projected_events(records) do
    records
    |> MissionEvents.project_many()
    |> then(&MissionEvents.persist_entries(Repo, &1))
  end
end
