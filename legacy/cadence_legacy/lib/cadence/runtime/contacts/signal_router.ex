defmodule Cadence.Runtime.Contacts.SignalRouter do
  @moduledoc """
  Routes transport connection signals to active contact runtimes.
  """

  use GenServer

  alias Cadence.Transports.Events.TransportConnectionEvent

  @registry Cadence.MissionRegistry

  @type state :: %{
          mission_id: String.t(),
          contact_routes: map(),
          transport_index: map()
        }

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @spec register(String.t(), String.t(), pid(), [String.t()]) :: :ok
  def register(mission_id, contact_id, pid, transport_ids) do
    case whereis(mission_id) do
      nil -> :ok
      server -> GenServer.call(server, {:register, contact_id, pid, transport_ids})
    end
  end

  @spec unregister(String.t(), String.t()) :: :ok
  def unregister(mission_id, contact_id) do
    case whereis(mission_id) do
      nil -> :ok
      server -> GenServer.call(server, {:unregister, contact_id})
    end
  end

  @impl true
  def init(mission_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")

    {:ok, %{mission_id: mission_id, contact_routes: %{}, transport_index: %{}}}
  end

  @impl true
  def handle_call({:register, contact_id, pid, transport_ids}, _from, state) do
    transport_ids = Enum.uniq(transport_ids)

    contact_routes =
      Map.put(state.contact_routes, contact_id, %{pid: pid, transport_ids: transport_ids})

    transport_index =
      Enum.reduce(transport_ids, state.transport_index, fn transport_id, acc ->
        Map.update(acc, transport_id, MapSet.new([contact_id]), fn existing ->
          MapSet.put(existing, contact_id)
        end)
      end)

    {:reply, :ok, %{state | contact_routes: contact_routes, transport_index: transport_index}}
  end

  @impl true
  def handle_call({:unregister, contact_id}, _from, state) do
    {contact_routes, transport_index} = remove_contact(contact_id, state)
    {:reply, :ok, %{state | contact_routes: contact_routes, transport_index: transport_index}}
  end

  @impl true
  def handle_info({:transport_connection_event, %TransportConnectionEvent{} = event}, state) do
    contact_ids = Map.get(state.transport_index, event.transport_id, MapSet.new())
    connected? = TransportConnectionEvent.connected?(event)

    Enum.each(contact_ids, fn contact_id ->
      case Map.get(state.contact_routes, contact_id) do
        %{pid: pid} when is_pid(pid) ->
          send(pid, {:signal, {:transport_connected, event.transport_id, connected?}})

        _ ->
          :ok
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp remove_contact(contact_id, state) do
    case Map.get(state.contact_routes, contact_id) do
      nil ->
        {state.contact_routes, state.transport_index}

      %{transport_ids: transport_ids} ->
        transport_index =
          Enum.reduce(transport_ids, state.transport_index, fn transport_id, acc ->
            update_transport_index(acc, transport_id, contact_id)
          end)

        {Map.delete(state.contact_routes, contact_id), transport_index}
    end
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:contact_signal_router, mission_id}}}
  end

  defp update_transport_index(transport_index, transport_id, contact_id) do
    case Map.get(transport_index, transport_id) do
      nil ->
        transport_index

      existing ->
        updated = MapSet.delete(existing, contact_id)

        if MapSet.size(updated) == 0 do
          Map.delete(transport_index, transport_id)
        else
          Map.put(transport_index, transport_id, updated)
        end
    end
  end

  defp whereis(mission_id) do
    case Registry.lookup(@registry, {:contact_signal_router, mission_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
