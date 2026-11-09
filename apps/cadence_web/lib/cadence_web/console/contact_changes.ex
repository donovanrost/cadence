defmodule CadenceWeb.Console.ContactChanges do
  @moduledoc """
  Relays committed contact facts (`Cadence.Contacts.Facts`: scheduled and
  realized contacts, contact actions) as per-mission notifications for console
  channels: `{:console_contacts_changed, mission_id}` on `topic(mission_id)`.
  The mission channel turns them into the `contacts` invalidation (S10).
  """

  use GenServer

  alias Cadence.Contacts.Facts
  alias Cadence.Platform.EventBus

  @pubsub Cadence.PubSub

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec topic(binary()) :: binary()
  def topic(mission_id) when is_binary(mission_id), do: "console:contact-changes:" <> mission_id

  @spec subscribe(binary()) :: :ok | {:error, term()}
  def subscribe(mission_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(mission_id))

  @impl true
  def init(opts) do
    :ok = Facts.subscribe(Keyword.get(opts, :event_bus, EventBus), self())
    {:ok, nil}
  end

  @impl true
  def handle_call({:cadence_fact, _topic, fact}, _from, state) do
    observe(fact)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:cadence_fact, _topic, fact}, state) do
    observe(fact)
    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @doc false
  @spec observe(term()) :: :ok
  def observe(%{mission_id: mission_id}) when is_binary(mission_id) do
    Phoenix.PubSub.broadcast(@pubsub, topic(mission_id), {:console_contacts_changed, mission_id})
  end

  def observe(_fact), do: :ok
end
