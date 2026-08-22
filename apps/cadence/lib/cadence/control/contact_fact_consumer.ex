defmodule Cadence.Control.ContactFactConsumer do
  @moduledoc "Reacts to committed Contact facts without coupling Contact transactions to Commanding."

  use GenServer

  alias Cadence.Commanding.ProcessNamespace
  alias Cadence.Contacts.Facts
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.Commanding
  alias Cadence.Platform.EventBus

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    event_bus = Keyword.get(opts, :event_bus, EventBus)

    process_namespace =
      Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)

    :ok = Facts.subscribe(event_bus, self())

    {:ok,
     %{
       notify_release_target:
         Keyword.get_lazy(opts, :notify_release_target, fn ->
           &Commanding.notify_release_target_available(&1, process_namespace)
         end)
     }}
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
         %RealizedContact{} = contact,
         %{notify_release_target: notify_release_target} = state
       ) do
    _result = notify_release_target.(contact)
    state
  end

  defp consume(_fact, state), do: state
end
