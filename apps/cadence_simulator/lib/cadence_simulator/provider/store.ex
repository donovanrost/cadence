defmodule CadenceSimulator.Provider.Store do
  @moduledoc """
  Durable store for provider scenarios, run snapshots, reservations, and events.

  The store intentionally uses DETS so the simulator remains an external peer
  and does not acquire a runtime dependency on Cadence's database.
  """

  use GenServer

  @table :cadence_simulator_provider_store

  @type resource_kind :: :scenario | :run | :reservation

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(resource_kind(), map()) :: {:ok, map()}
  def put(kind, %{"id" => id} = resource) when kind in [:scenario, :run, :reservation] do
    GenServer.call(__MODULE__, {:put, kind, id, resource})
  end

  @spec fetch(resource_kind(), binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch(kind, id) when kind in [:scenario, :run, :reservation] and is_binary(id) do
    GenServer.call(__MODULE__, {:fetch, kind, id})
  end

  @spec list(resource_kind()) :: [map()]
  def list(kind) when kind in [:scenario, :run, :reservation] do
    GenServer.call(__MODULE__, {:list, kind})
  end

  @spec append_event(map()) :: {:ok, map()}
  def append_event(event) when is_map(event) do
    GenServer.call(__MODULE__, {:append_event, event})
  end

  @spec events(non_neg_integer(), pos_integer()) :: %{
          data: [map()],
          next_cursor: non_neg_integer()
        }
  def events(cursor \\ 0, limit \\ 100)
      when is_integer(cursor) and cursor >= 0 and is_integer(limit) and limit > 0 do
    GenServer.call(__MODULE__, {:events, cursor, min(limit, 500)})
  end

  @doc false
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    :ok = File.mkdir_p(Path.dirname(path))

    case :dets.open_file(@table, type: :set, file: String.to_charlist(path)) do
      {:ok, @table} -> {:ok, %{table: @table, path: path}}
      {:error, reason} -> {:stop, {:provider_store_open_failed, path, reason}}
    end
  end

  @impl true
  def handle_call({:put, kind, id, resource}, _from, state) do
    :ok = :dets.insert(state.table, {{kind, id}, resource})
    :ok = :dets.sync(state.table)
    {:reply, {:ok, resource}, state}
  end

  def handle_call({:fetch, kind, id}, _from, state) do
    reply =
      case :dets.lookup(state.table, {kind, id}) do
        [{{^kind, ^id}, resource}] -> {:ok, resource}
        [] -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:list, kind}, _from, state) do
    resources =
      :dets.foldl(
        fn
          {{^kind, _id}, resource}, acc -> [resource | acc]
          _other, acc -> acc
        end,
        [],
        state.table
      )
      |> Enum.sort_by(&Map.get(&1, "created_at", ""), :desc)

    {:reply, resources, state}
  end

  def handle_call({:append_event, event}, _from, state) do
    sequence = next_sequence(state.table)

    stored_event =
      event
      |> Map.put("id", "event-#{sequence}")
      |> Map.put("sequence", sequence)
      |> Map.put_new("occurred_at", DateTime.utc_now() |> DateTime.to_iso8601())

    :ok = :dets.insert(state.table, {{:event, sequence}, stored_event})
    :ok = :dets.insert(state.table, {{:metadata, :event_sequence}, sequence})
    :ok = :dets.sync(state.table)
    {:reply, {:ok, stored_event}, state}
  end

  def handle_call({:events, cursor, limit}, _from, state) do
    data =
      :dets.foldl(
        fn
          {{:event, sequence}, event}, acc when sequence > cursor -> [event | acc]
          _other, acc -> acc
        end,
        [],
        state.table
      )
      |> Enum.sort_by(&Map.fetch!(&1, "sequence"))
      |> Enum.take(limit)

    next_cursor =
      case List.last(data) do
        nil -> cursor
        event -> Map.fetch!(event, "sequence")
      end

    {:reply, %{data: data, next_cursor: next_cursor}, state}
  end

  def handle_call(:clear, _from, state) do
    :ok = :dets.delete_all_objects(state.table)
    :ok = :dets.sync(state.table)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    :dets.close(state.table)
  end

  defp next_sequence(table) do
    case :dets.lookup(table, {:metadata, :event_sequence}) do
      [{{:metadata, :event_sequence}, sequence}] -> sequence + 1
      [] -> 1
    end
  end
end
