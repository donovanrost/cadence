defmodule Cadence.Platform.EventBus do
  @moduledoc """
  Plane-neutral in-process transport for typed cross-plane facts.

  Publishers depend only on this platform boundary and on fact types owned by
  the producer. Subscribers register their process at runtime, so the event bus
  never acquires a compile-time dependency on a plane implementation.

  Delivery is queued after the producer's authoritative transaction commits.
  A slow, missing, or failed subscriber cannot block or roll back the producer;
  durable owners remain responsible for reconciliation after missed delivery.

  Tests may select synchronous delivery to make cross-plane integration
  assertions deterministic. Subscriber work still happens outside the event
  bus process, so nested publications cannot deadlock the bus.
  """

  use GenServer

  @type server :: GenServer.server()
  @type topic :: term()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec subscribe(topic()) :: :ok
  def subscribe(topic), do: subscribe(__MODULE__, topic, self())

  @spec subscribe(topic(), GenServer.server()) :: :ok
  def subscribe(topic, subscriber), do: subscribe(__MODULE__, topic, subscriber)

  @spec subscribe(server(), topic(), GenServer.server()) :: :ok
  def subscribe(server, topic, subscriber) do
    case GenServer.whereis(server) do
      nil -> :ok
      event_bus -> GenServer.call(event_bus, {:subscribe, topic, subscriber})
    end
  end

  @spec publish(topic(), term()) :: :ok
  def publish(topic, fact), do: publish(__MODULE__, topic, fact)

  @spec publish(server(), topic(), term()) :: :ok
  def publish(server, topic, fact) do
    case GenServer.whereis(server) do
      nil ->
        :ok

      event_bus ->
        {:deliver, subscribers, delivery, before_notify} =
          GenServer.call(event_bus, {:prepare_publish, topic})

        Enum.each(subscribers, fn subscriber ->
          notify_subscriber(subscriber, topic, fact, self(), delivery, before_notify)
        end)
    end
  end

  @impl true
  def init(opts) do
    {delivery, before_notify} = delivery_options(opts)

    {:ok,
     %{
       subscribers: %{},
       monitors: %{},
       delivery: delivery,
       before_notify: before_notify
     }}
  end

  @impl true
  def handle_call({:subscribe, topic, subscriber}, _from, state) do
    pid = resolve_pid!(subscriber)

    subscribers =
      Map.update(state.subscribers, topic, MapSet.new([pid]), &MapSet.put(&1, pid))

    {monitors, _ref} = ensure_monitored(state.monitors, pid)
    {:reply, :ok, %{state | subscribers: subscribers, monitors: monitors}}
  end

  def handle_call({:prepare_publish, topic}, _from, state) do
    subscribers = state.subscribers |> Map.get(topic, MapSet.new()) |> MapSet.to_list()
    {:reply, {:deliver, subscribers, state.delivery, state.before_notify}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    subscribers =
      Map.new(state.subscribers, fn {topic, subscribers} ->
        {topic, MapSet.delete(subscribers, pid)}
      end)

    {:noreply, %{state | subscribers: subscribers, monitors: Map.delete(state.monitors, ref)}}
  end

  defp resolve_pid!(pid) when is_pid(pid), do: pid

  defp resolve_pid!(name) when is_atom(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) -> pid
      nil -> raise ArgumentError, "event bus subscriber #{inspect(name)} is not running"
    end
  end

  defp ensure_monitored(monitors, pid) do
    case Enum.find(monitors, fn {_ref, monitored_pid} -> monitored_pid == pid end) do
      {ref, ^pid} ->
        {monitors, ref}

      nil ->
        ref = Process.monitor(pid)
        {Map.put(monitors, ref, pid), ref}
    end
  end

  defp delivery_options(opts) do
    case {Keyword.fetch(opts, :delivery), Keyword.fetch(opts, :before_notify)} do
      {{:ok, delivery}, {:ok, before_notify}} ->
        {delivery, before_notify}

      _incomplete ->
        config = Application.get_env(:cadence, :event_bus, [])

        {
          Keyword.get(opts, :delivery, Keyword.get(config, :delivery, :async)),
          Keyword.get(opts, :before_notify, Keyword.get(config, :before_notify))
        }
    end
  end

  defp notify_subscriber(pid, topic, fact, publisher, delivery, before_notify) do
    run_before_notify(before_notify, publisher, pid)

    case delivery do
      :sync -> notify_subscriber_sync(pid, topic, fact)
      :async -> GenServer.cast(pid, {:cadence_fact, topic, fact})
    end
  end

  defp notify_subscriber_sync(pid, topic, fact) do
    _reply = GenServer.call(pid, {:cadence_fact, topic, fact}, :infinity)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp run_before_notify(nil, _publisher, _subscriber), do: :ok

  defp run_before_notify({module, function, leading_args}, publisher, subscriber)
       when is_atom(module) and is_atom(function) and is_list(leading_args) do
    _result = apply(module, function, leading_args ++ [publisher, subscriber])
    :ok
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end
end
