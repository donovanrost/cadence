defmodule Cadence.Ingress.BackpressureMonitor do
  @moduledoc """
  Watches ingest backpressure for the `ingress_backpressure` attention source (DECISIONS #83).

  - **Buffer filling** (`journal_near_full`): every few seconds it reads each running contact's
    ingress journal (`retained / capacity`). An item opens at 80% and clears below 70% (or when
    the journal goes away: the contact ended and drained). `rising` is true while the ratio grew
    since the previous sample.
  - **Frames dropped** (`frames_dropped`): it listens for `ReceiveBackpressure`'s
    `[:cadence, :ingress, :frames_dropped]` event, so a transport that can't push back counts its
    drops here. A drop is data loss: the item stays until an operator acknowledges it and the
    contact has ended.

  State is in this process, so it lasts the node's lifetime (a restart clears the backlog too).
  Flips publish `:attention_changed` for the mission. Never crashes the runtime root
  (`:one_for_all`): every call into another process is guarded.
  """

  use GenServer

  require Logger

  alias Cadence.Ingress.ReceiveBackpressure
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Runtime.{Cluster, ProcessNamespace}

  @raise_ratio 0.8
  @clear_ratio 0.7
  @default_interval_ms 5_000
  @resolved_keep_s 120

  @type key :: {binary(), binary(), binary()}

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :permanent}
  end

  def start_link(opts) do
    namespace = Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)

    GenServer.start_link(__MODULE__, Keyword.put(opts, :process_namespace, namespace),
      name: name(namespace)
    )
  end

  @doc "The monitor of a runtime namespace."
  def name(%ProcessNamespace{} = namespace),
    do: ProcessNamespace.via(namespace, :ingress_backpressure_monitor)

  @doc "What one mission has open and recently resolved; empty when the monitor isn't running."
  @spec snapshot(binary(), ProcessNamespace.t()) :: %{
          near_full: [map()],
          drops: [map()],
          resolved: [map()]
        }
  def snapshot(mission_id, namespace \\ ProcessNamespace.default()) do
    GenServer.call(name(namespace), {:snapshot, mission_id}, 1_000)
  catch
    :exit, _reason -> %{near_full: [], drops: [], resolved: []}
  end

  @doc "Records an operator's acknowledgement of a mission's dropped frames."
  @spec acknowledge(binary(), key(), map(), ProcessNamespace.t()) ::
          {:ok, map()} | {:error, term()}
  def acknowledge(mission_id, key, actor, namespace \\ ProcessNamespace.default()) do
    GenServer.call(name(namespace), {:acknowledge, mission_id, key, actor}, 1_000)
  catch
    :exit, _reason -> {:error, :attention_item_not_found}
  end

  @doc false
  def sample_now(namespace \\ ProcessNamespace.default()),
    do: GenServer.call(name(namespace), :sample, 5_000)

  @impl true
  def init(opts) do
    handler = {__MODULE__, self()}
    monitor = self()

    :ok =
      :telemetry.attach(
        handler,
        ReceiveBackpressure.dropped_event(),
        fn _event, measurements, metadata, _config ->
          send(monitor, {:frames_dropped, measurements, metadata, DateTime.utc_now()})
        end,
        nil
      )

    state = %{
      namespace: Keyword.fetch!(opts, :process_namespace),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      handler: handler,
      usage: %{},
      near_full: %{},
      drops: %{},
      resolved: [],
      organizations: %{}
    }

    {:ok, schedule(state)}
  end

  @impl true
  def terminate(_reason, state), do: :telemetry.detach(state.handler)

  @impl true
  def handle_info(:tick, state), do: {:noreply, state |> sample() |> schedule()}

  def handle_info({:frames_dropped, measurements, metadata, at}, state) do
    case key(metadata) do
      nil -> {:noreply, state}
      key -> {:noreply, record_drop(state, key, measurements, metadata, at)}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call({:snapshot, mission_id}, _from, state) do
    {:reply,
     %{
       near_full:
         for(
           {{^mission_id, _, _} = key, raised_at} <- state.near_full,
           do: near_full(state, key, raised_at)
         ),
       drops: for({{^mission_id, _, _} = key, drop} <- state.drops, do: Map.put(drop, :key, key)),
       resolved: for(%{key: {^mission_id, _, _}} = entry <- state.resolved, do: entry)
     }, state}
  end

  def handle_call({:acknowledge, mission_id, {mission_id, _, _} = key, actor}, _from, state) do
    case Map.fetch(state.drops, key) do
      {:ok, %{acknowledged_by: nil} = drop} ->
        drop = %{drop | acknowledged_by: actor, acknowledged_at: DateTime.utc_now()}
        state = state |> put_in([:drops, key], drop) |> settle_drops() |> publish(mission_id)
        {:reply, {:ok, Map.put(drop, :key, key)}, state}

      _missing_or_done ->
        {:reply, {:error, :attention_item_not_found}, state}
    end
  end

  def handle_call({:acknowledge, _mission_id, _key, _actor}, _from, state),
    do: {:reply, {:error, :attention_item_not_found}, state}

  def handle_call(:sample, _from, state), do: {:reply, :ok, sample(state)}

  defp schedule(state) do
    Process.send_after(self(), :tick, state.interval_ms)
    state
  end

  # One pass over every running journal: usage, then opening and clearing near-full items.
  defp sample(state) do
    now = DateTime.utc_now()

    usage =
      state.namespace
      |> journals()
      |> Enum.map(&usage(&1, state.usage, now))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    state
    |> Map.put(:usage, usage)
    |> open_near_full(usage, now)
    |> clear_near_full(usage, now)
    |> settle_drops()
    |> forget_old(now)
  rescue
    error ->
      Logger.warning("ingress backpressure sample failed: #{Exception.message(error)}")
      state
  end

  defp open_near_full(state, usage, now) do
    Enum.reduce(usage, state, fn {key, %{ratio: ratio}}, acc ->
      if ratio >= @raise_ratio and not Map.has_key?(acc.near_full, key) do
        acc |> put_in([:near_full, key], now) |> publish(elem(key, 0))
      else
        acc
      end
    end)
  end

  defp clear_near_full(state, usage, now) do
    Enum.reduce(state.near_full, state, fn {key, _raised_at}, acc ->
      if clear?(Map.get(usage, key)) do
        acc
        |> update_in([:near_full], &Map.delete(&1, key))
        |> resolve(key, "journal_near_full", "drained", %{"kind" => "system"}, now)
        |> publish(elem(key, 0))
      else
        acc
      end
    end)
  end

  defp clear?(nil), do: true
  defp clear?(%{ratio: ratio}), do: ratio < @clear_ratio

  # A dropped-frames item resolves once acknowledged AND its contact's runtime is gone.
  defp settle_drops(state) do
    Enum.reduce(state.drops, state, fn
      {key, %{acknowledged_by: by, acknowledged_at: at}}, acc when not is_nil(by) ->
        if contact_running?(acc.namespace, key) do
          acc
        else
          acc
          |> update_in([:drops], &Map.delete(&1, key))
          |> resolve(key, "frames_dropped", "acknowledged", by, at)
          |> publish(elem(key, 0))
        end

      _open, acc ->
        acc
    end)
  end

  defp record_drop(state, key, measurements, metadata, at) do
    count = Map.get(measurements, :count, 1)
    bytes = Map.get(measurements, :bytes, 0)

    {state, new?} =
      case Map.fetch(state.drops, key) do
        {:ok, drop} ->
          {put_in(state, [:drops, key], %{
             drop
             | count: drop.count + count,
               bytes: drop.bytes + bytes,
               last_at: at
           }), false}

        :error ->
          drop = %{
            count: count,
            bytes: bytes,
            first_at: at,
            last_at: at,
            buffer: to_string(Map.get(metadata, :buffer, "executor")),
            acknowledged_by: nil,
            acknowledged_at: nil
          }

          {put_in(state, [:drops, key], drop), true}
      end

    if new?, do: publish(state, elem(key, 0)), else: state
  end

  defp resolve(state, {_mission, _contact, _binding} = key, conflict, action, by, at) do
    entry = %{key: key, conflict: conflict, resolved_by: by, action: action, resolved_at: at}
    %{state | resolved: [entry | state.resolved]}
  end

  defp forget_old(state, now) do
    cutoff = DateTime.add(now, -@resolved_keep_s, :second)

    %{
      state
      | resolved: Enum.filter(state.resolved, &(DateTime.compare(&1.resolved_at, cutoff) == :gt))
    }
  end

  defp near_full(state, key, raised_at) do
    Map.merge(Map.get(state.usage, key, %{}), %{key: key, raised_at: raised_at})
  end

  defp usage({mission, contact, binding, pid}, previous, now) do
    key = {mission, contact, binding}

    case journal_snapshot(pid) do
      {:ok, snapshot} ->
        ratio = snapshot.retained_bytes / max(snapshot.max_bytes, 1)
        before = Map.get(previous, key)

        {key,
         %{
           used_bytes: snapshot.retained_bytes,
           capacity_bytes: snapshot.max_bytes,
           ratio: Float.round(ratio, 4),
           threshold: @raise_ratio,
           backlog_bytes: backlog_bytes(snapshot),
           observed_at: now,
           rising: is_map(before) and ratio > before.ratio,
           stream_id: snapshot.stream_id,
           last_error: snapshot.last_error
         }}

      :error ->
        {key, Map.get(previous, key)}
    end
  end

  defp backlog_bytes(%{processing_backlog: %{bytes: bytes}}) when is_integer(bytes), do: bytes
  defp backlog_bytes(%{lag_bytes: %{processing: bytes}}) when is_integer(bytes), do: bytes
  defp backlog_bytes(_snapshot), do: 0

  defp journal_snapshot(pid) do
    case IngressJournal.snapshot(pid) do
      {:ok, %{retained_bytes: _, max_bytes: _} = snapshot} -> {:ok, snapshot}
      _other -> :error
    end
  catch
    :exit, _reason -> :error
  end

  defp journals(namespace) do
    Cluster.select(namespace, [
      {{{:provider_ingress_journal, :"$1", :"$2", :_, :"$3"}, :"$4", :_}, [],
       [{{:"$1", :"$2", :"$3", :"$4"}}]}
    ])
  catch
    :exit, _reason -> []
  end

  defp contact_running?(namespace, {mission, contact, _binding}) do
    Cluster.select(namespace, [
      {{{:provider_ingress_executor, mission, contact, :_, :_}, :_, :_}, [], [true]}
    ]) != []
  catch
    :exit, _reason -> false
  end

  defp key(%{mission_id: mission, realized_contact_id: contact, provider_binding_id: binding})
       when is_binary(mission) and is_binary(contact) and is_binary(binding),
       do: {mission, contact, binding}

  defp key(_metadata), do: nil

  defp publish(state, mission_id) do
    case organization(state, mission_id) do
      {nil, state} ->
        state

      {organization_id, state} ->
        _ = ScopedReadUpdates.publish(:attention_changed, organization_id, mission_id)
        state
    end
  end

  defp organization(state, mission_id) do
    case Map.fetch(state.organizations, mission_id) do
      {:ok, organization_id} ->
        {organization_id, state}

      :error ->
        organization_id = Cadence.Missions.organization_id_for_mission(mission_id)
        {organization_id, put_in(state, [:organizations, mission_id], organization_id)}
    end
  rescue
    _error -> {nil, state}
  end
end
