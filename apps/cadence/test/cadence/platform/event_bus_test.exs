defmodule Cadence.Platform.EventBusTest do
  use ExUnit.Case, async: false
  use GenServer

  alias Cadence.Platform.EventBus

  @named_bus __MODULE__.NamedBus
  @missing_bus __MODULE__.MissingBus

  @fact_facades [
    {Cadence.Activations.Facts, {:cadence, :activations, :facts}},
    {Cadence.Catalog.Facts, {:cadence, :catalog, :facts}},
    {Cadence.Contacts.Facts, {:cadence, :contacts, :facts}},
    {Cadence.DataSources.Facts, {:cadence, :data_sources, :facts}},
    {Cadence.Limits.Facts, {:cadence, :limits, :facts}},
    {Cadence.Runtime.Facts, {:cadence, :runtime, :facts}},
    {Cadence.Telemetry.Facts, {:cadence, :telemetry, :facts}}
  ]

  test "synchronous subscribers receive publications only from their event bus" do
    publisher = self()
    topic = {:event_bus_instances, make_ref()}

    bus_a =
      start_bus(
        name: nil,
        delivery: :sync,
        before_notify: {__MODULE__, :before_notify, [self(), :bus_a]}
      )

    _bus_b =
      start_bus(
        name: @named_bus,
        delivery: :sync,
        before_notify: {__MODULE__, :before_notify, [self(), :bus_b]}
      )

    subscriber_a = start_subscriber(:bus_a)
    subscriber_b = start_subscriber(:bus_b)

    assert :ok = EventBus.subscribe(bus_a, topic, subscriber_a)
    assert :ok = EventBus.subscribe(@named_bus, topic, subscriber_b)

    assert :ok = EventBus.publish(bus_a, topic, :fact_a)
    assert_receive {:before_notify, :bus_a, ^publisher, ^subscriber_a}
    assert_receive {:cadence_fact, :bus_a, :sync, ^topic, :fact_a}
    refute_receive {:before_notify, :bus_b, _, _}
    refute_receive {:cadence_fact, :bus_b, _, _, _}

    bus_b_address = {@named_bus, node()}

    assert :ok = EventBus.publish(bus_b_address, topic, :fact_b)
    assert_receive {:before_notify, :bus_b, ^publisher, ^subscriber_b}
    assert_receive {:cadence_fact, :bus_b, :sync, ^topic, :fact_b}
    refute_receive {:cadence_fact, :bus_a, _, ^topic, :fact_b}
  end

  test "asynchronous subscribers receive publications only from their event bus" do
    topic = {:event_bus_instances, make_ref()}
    bus_a = start_bus(name: nil, delivery: :async, before_notify: nil)
    bus_b = start_bus(name: nil, delivery: :async, before_notify: nil)
    subscriber_a = start_subscriber(:bus_a)
    subscriber_b = start_subscriber(:bus_b)

    assert :ok = EventBus.subscribe(bus_a, topic, subscriber_a)
    assert :ok = EventBus.subscribe(bus_b, topic, subscriber_b)

    assert :ok = EventBus.publish(bus_a, topic, :fact_a)
    assert_receive {:cadence_fact, :bus_a, :async, ^topic, :fact_a}
    refute_receive {:cadence_fact, :bus_b, _, _, _}

    assert :ok = EventBus.publish(bus_b, topic, :fact_b)
    assert_receive {:cadence_fact, :bus_b, :async, ^topic, :fact_b}
    refute_receive {:cadence_fact, :bus_a, _, ^topic, :fact_b}
  end

  test "complete explicit options do not rediscover mutable application config" do
    previous_config = Application.fetch_env(:cadence, :event_bus)
    Application.put_env(:cadence, :event_bus, nil)

    on_exit(fn -> restore_application_env(:event_bus, previous_config) end)

    bus = start_bus(name: nil, delivery: :sync, before_notify: nil)

    assert %{delivery: :sync, before_notify: nil} = :sys.get_state(bus)
  end

  test "incomplete legacy options retain the application config fallback" do
    previous_config = Application.fetch_env(:cadence, :event_bus)
    before_notify = {__MODULE__, :before_notify, [self(), :legacy]}
    Application.put_env(:cadence, :event_bus, delivery: :sync, before_notify: before_notify)

    on_exit(fn -> restore_application_env(:event_bus, previous_config) end)

    bus = start_bus(name: nil)

    assert %{delivery: :sync, before_notify: ^before_notify} = :sys.get_state(bus)
  end

  test "subscriber death removes its subscriptions and monitor from only that bus" do
    topic = {:event_bus_instances, make_ref()}
    bus = start_bus(name: nil, delivery: :async, before_notify: nil)
    subscriber = start_subscriber(:departed)
    subscriber_monitor = Process.monitor(subscriber)

    assert :ok = EventBus.subscribe(bus, topic, subscriber)
    assert MapSet.member?(:sys.get_state(bus).subscribers[topic], subscriber)

    Process.exit(subscriber, :kill)
    assert_receive {:DOWN, ^subscriber_monitor, :process, ^subscriber, :killed}

    assert eventually(fn ->
             state = :sys.get_state(bus)
             state.monitors == %{} and state.subscribers[topic] == MapSet.new()
           end)

    assert :ok = EventBus.publish(bus, topic, :after_subscriber_death)
    refute_receive {:cadence_fact, :departed, _, _, _}
    assert Process.alive?(bus)
  end

  test "compatibility arities use the production event bus and preserve missing-bus no-ops" do
    production_bus = Process.whereis(EventBus)
    topic = {:event_bus_compatibility, make_ref()}
    self_topic = {:event_bus_compatibility, make_ref()}
    subscriber = start_subscriber(:production)

    assert is_pid(production_bus)
    assert :ok = EventBus.subscribe(topic, subscriber)
    assert MapSet.member?(:sys.get_state(production_bus).subscribers[topic], subscriber)

    assert :ok = EventBus.publish(topic, :production_fact)
    assert_receive {:cadence_fact, :production, :sync, ^topic, :production_fact}

    assert :ok = EventBus.subscribe(self_topic)
    assert MapSet.member?(:sys.get_state(production_bus).subscribers[self_topic], self())

    assert :ok = EventBus.subscribe(@missing_bus, topic, subscriber)
    assert :ok = EventBus.publish(@missing_bus, topic, :missing_bus_fact)
  end

  test "each fact facade accepts an explicit event bus" do
    bus = start_bus(name: nil, delivery: :sync, before_notify: nil)

    Enum.each(@fact_facades, fn {facade, topic} ->
      subscriber = start_subscriber(facade)
      fact = {:fact_from, facade}

      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert :ok = apply(facade, :subscribe, [bus, subscriber])
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert :ok = apply(facade, :publish, [bus, fact])
      assert_receive {:cadence_fact, ^facade, :sync, ^topic, ^fact}
    end)
  end

  def before_notify(owner, bus, publisher, subscriber) do
    send(owner, {:before_notify, bus, publisher, subscriber})
  end

  @impl true
  def init({owner, label}), do: {:ok, %{owner: owner, label: label}}

  @impl true
  def handle_call({:cadence_fact, topic, fact}, _from, state) do
    send(state.owner, {:cadence_fact, state.label, :sync, topic, fact})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:cadence_fact, topic, fact}, state) do
    send(state.owner, {:cadence_fact, state.label, :async, topic, fact})
    {:noreply, state}
  end

  defp start_bus(opts) do
    start_supervised!(%{
      id: {:event_bus, make_ref()},
      start: {EventBus, :start_link, [opts]},
      restart: :temporary
    })
  end

  defp start_subscriber(label) do
    start_supervised!(%{
      id: {:subscriber, make_ref()},
      start: {GenServer, :start_link, [__MODULE__, {self(), label}]},
      restart: :temporary
    })
  end

  defp restore_application_env(key, {:ok, value}),
    do: Application.put_env(:cadence, key, value)

  defp restore_application_env(key, :error), do: Application.delete_env(:cadence, key)

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(5)
      eventually(fun, attempts - 1)
    end
  end
end
