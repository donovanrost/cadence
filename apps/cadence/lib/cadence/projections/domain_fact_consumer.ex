defmodule Cadence.Projections.DomainFactConsumer do
  @moduledoc "Projects committed authoritative domain facts into mission timeline rows."

  use GenServer

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Activations.Facts, as: ActivationFacts
  alias Cadence.Contacts.ContactAction
  alias Cadence.Contacts.Facts, as: ContactFacts
  alias Cadence.Limits.Event, as: LimitEvent
  alias Cadence.Limits.Facts, as: LimitFacts
  alias Cadence.Platform.EventBus
  alias Cadence.Projections.MissionEvents
  alias Cadence.Repo

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    event_bus = Keyword.get(opts, :event_bus, EventBus)
    :ok = ActivationFacts.subscribe(event_bus, self())
    :ok = ContactFacts.subscribe(event_bus, self())
    :ok = LimitFacts.subscribe(event_bus, self())

    {:ok, %{project_fact: Keyword.get(opts, :project_fact, &project_fact/1)}}
  end

  @impl true
  def handle_call({:cadence_fact, _topic, fact}, _from, state) do
    {:reply, :ok, consume(fact, state)}
  end

  @impl true
  def handle_cast({:cadence_fact, _topic, fact}, state) do
    {:noreply, consume(fact, state)}
  end

  defp consume(fact, %{project_fact: project_fact} = state)
       when is_struct(fact, BindingSetActivation) or is_struct(fact, ContactAction) or
              is_struct(fact, LimitEvent) do
    project_fact.(fact)
    state
  end

  defp consume(_fact, state), do: state

  defp project_fact(fact) do
    fact
    |> MissionEvents.project()
    |> then(&MissionEvents.persist_entries(Repo, &1))
  end
end
