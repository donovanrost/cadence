defmodule Cadence.Control.RuntimeFactConsumer do
  @moduledoc """
  Control-plane consumer for durable data-plane observations.

  Transport and telemetry verifier evaluation is intentionally downstream of
  the Runtime transaction. Missed delivery can be reconciled from the durable
  runtime records without coupling the data-plane commit to Control.
  """

  use GenServer

  alias Cadence.Commanding.ProcessNamespace
  alias Cadence.Control.Commanding
  alias Cadence.Platform.EventBus
  alias Cadence.Runtime.{Facts, ProcessingResultsPersisted, TransportRecordsPersisted}

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
       evaluate_telemetry:
         Keyword.get_lazy(opts, :evaluate_telemetry, fn ->
           &Commanding.evaluate_command_verifiers(&1, process_namespace)
         end),
       evaluate_transport:
         Keyword.get_lazy(opts, :evaluate_transport, fn ->
           &Commanding.evaluate_transport_command_verifiers(&1, &2, process_namespace)
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
         %ProcessingResultsPersisted{telemetry_samples: samples},
         %{evaluate_telemetry: evaluate_telemetry} = state
       ) do
    _result = evaluate_telemetry.(samples)
    state
  end

  defp consume(
         %TransportRecordsPersisted{
           capability_records: capability_records,
           action_requests: action_requests
         },
         %{evaluate_transport: evaluate_transport} = state
       ) do
    _result = evaluate_transport.(capability_records, action_requests)
    state
  end

  defp consume(_fact, state), do: state
end
