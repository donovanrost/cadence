defmodule Cadence.Control.RuntimeFactConsumer do
  @moduledoc """
  Control-plane consumer for durable data-plane observations.

  Transport and telemetry verifier evaluation is intentionally downstream of
  the Runtime transaction. Missed delivery can be reconciled from the durable
  runtime records without coupling the data-plane commit to Control.
  """

  use GenServer

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
    :ok = Facts.subscribe(event_bus, self())

    {:ok,
     %{
       evaluate_telemetry:
         Keyword.get(opts, :evaluate_telemetry, &Commanding.evaluate_command_verifiers/1),
       evaluate_transport:
         Keyword.get(
           opts,
           :evaluate_transport,
           &Commanding.evaluate_transport_command_verifiers/2
         )
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
