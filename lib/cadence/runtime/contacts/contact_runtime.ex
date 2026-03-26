defmodule Cadence.Runtime.Contacts.ContactRuntime do
  @moduledoc """
  Per-contact runtime worker that evaluates readiness gates and executes actions.
  """

  use GenServer

  alias Cadence.Ports.Contacts.ActionClaimer
  alias Cadence.Runtime.Contacts.GateEngine
  alias Cadence.Time.Timer, as: TimeTimer

  require Logger

  @default_retry_interval_ms 2_000

  @type state :: %{
          mission_id: String.t(),
          organization_id: String.t(),
          contact: map(),
          contact_id: String.t(),
          transport_ids: [String.t()],
          uplink_transport_id: String.t() | nil,
          gate_engine: GateEngine.t(),
          pending_actions: list(),
          retry_refs: map(),
          unavailable_actions: MapSet.t(),
          action_claimer: module(),
          action_executor: module(),
          timer_module: module(),
          retry_interval_ms: non_neg_integer(),
          events_topic: String.t()
        }

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    contact = Keyword.fetch!(opts, :contact)
    contact_id = Map.get(contact, :id)
    name = Keyword.get(opts, :name, via_tuple(mission_id, contact_id))

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    contact = Keyword.fetch!(opts, :contact)

    %{
      id: {__MODULE__, Map.get(contact, :id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec signal(String.t(), String.t(), term()) :: :ok
  def signal(mission_id, contact_id, signal) do
    case whereis(mission_id, contact_id) do
      nil -> :ok
      pid -> send(pid, {:signal, signal})
    end
  end

  @spec end_contact(String.t(), String.t()) :: :ok
  def end_contact(mission_id, contact_id) do
    case whereis(mission_id, contact_id) do
      nil -> :ok
      pid -> send(pid, :contact_end)
    end
  end

  @spec whereis(String.t(), String.t()) :: pid() | nil
  def whereis(mission_id, contact_id) do
    case Registry.lookup(Cadence.MissionRegistry, {:contact_runtime, mission_id, contact_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    organization_id = Keyword.fetch!(opts, :organization_id)
    contact = Keyword.fetch!(opts, :contact)
    transport_ids = Keyword.get(opts, :transport_ids, [])
    uplink_transport_id = Keyword.get(opts, :uplink_transport_id)
    actions = Keyword.get(opts, :actions, [])

    gate_engine =
      GateEngine.new(
        transport_ids: transport_ids,
        uplink_transport_id: uplink_transport_id,
        gates: [:active, :uplink_ready]
      )

    state = %{
      mission_id: mission_id,
      organization_id: organization_id,
      contact: contact,
      contact_id: Map.get(contact, :id),
      transport_ids: transport_ids,
      uplink_transport_id: uplink_transport_id,
      gate_engine: gate_engine,
      pending_actions: actions,
      retry_refs: %{},
      unavailable_actions: MapSet.new(),
      action_claimer: Keyword.get(opts, :action_claimer, ActionClaimer.impl()),
      action_executor:
        Keyword.get(opts, :action_executor, Cadence.Application.Contacts.CommandActionExecutor),
      timer_module: Keyword.get(opts, :timer_module, TimeTimer),
      retry_interval_ms: Keyword.get(opts, :retry_interval_ms, @default_retry_interval_ms),
      events_topic: "mission:#{mission_id}:events"
    }

    send(self(), :initialize)
    {:ok, state}
  end

  @impl true
  def handle_info(:initialize, state) do
    {:noreply, process_gate(:active, %{reason: "contact_started"}, state)}
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    {gate_engine, events} = GateEngine.ingest_signal(state.gate_engine, signal)
    state = %{state | gate_engine: gate_engine}

    state =
      Enum.reduce(events, state, fn {:gate_satisfied, gate, details}, acc ->
        process_gate(gate, details, acc)
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:retry_action, action_id}, state) do
    state = %{state | retry_refs: Map.delete(state.retry_refs, action_id)}

    case find_action(state.pending_actions, action_id) do
      nil ->
        {:noreply, state}

      action ->
        if gate_satisfied?(state, action.gate) do
          {:noreply, attempt_action(action, state)}
        else
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(:contact_end, state) do
    {:stop, :normal, skip_pending_actions(state)}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp process_gate(:active, _details, state) do
    attempt_actions_for_gate(:active, state)
  end

  defp process_gate(gate, details, state) do
    publish_contact_ready(gate, details, state)
    attempt_actions_for_gate(gate, state)
  end

  defp attempt_actions_for_gate(gate, state) do
    eligible_actions =
      state.pending_actions
      |> Enum.filter(fn action -> action.gate == gate end)
      |> Enum.reject(fn action -> Map.has_key?(state.retry_refs, action.id) end)

    Enum.reduce(eligible_actions, state, fn action, acc -> attempt_action(action, acc) end)
  end

  defp attempt_action(action, state) do
    context = %{
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      actor_id: nil
    }

    case state.action_claimer.claim(action, context) do
      :ok ->
        execute_action(action, state)

      {:error, :already_claimed} ->
        finalize_action(action, state, :already_claimed)

      {:error, reason} ->
        schedule_retry(action, reason, state)
    end
  end

  defp execute_action(action, state) do
    context = %{
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      contact: state.contact,
      actor_id: nil
    }

    case state.action_executor.execute(action, context) do
      {:ok, result} ->
        publish_action_event(:contact_action_completed, action, %{result: result}, state)
        finalize_action(action, state, :completed)

      :ok ->
        publish_action_event(:contact_action_completed, action, %{result: %{}}, state)
        finalize_action(action, state, :completed)

      {:error, reason} ->
        {code, message} = normalize_error(reason)

        publish_action_event(
          :contact_action_failed,
          action,
          %{error_code: code, error_message: message},
          state
        )

        finalize_action(action, state, :failed)
    end
  end

  defp schedule_retry(action, _reason, state) do
    retry_ref =
      state.timer_module.send_after(self(), {:retry_action, action.id}, state.retry_interval_ms)

    retry_refs = Map.put(state.retry_refs, action.id, retry_ref)
    unavailable_actions = MapSet.put(state.unavailable_actions, action.id)

    %{state | retry_refs: retry_refs, unavailable_actions: unavailable_actions}
  end

  defp finalize_action(action, state, _result) do
    pending_actions = Enum.reject(state.pending_actions, fn item -> item.id == action.id end)
    retry_refs = Map.delete(state.retry_refs, action.id)
    unavailable_actions = MapSet.delete(state.unavailable_actions, action.id)

    %{
      state
      | pending_actions: pending_actions,
        retry_refs: retry_refs,
        unavailable_actions: unavailable_actions
    }
  end

  defp skip_pending_actions(state) do
    Enum.reduce(state.pending_actions, state, fn action, acc ->
      reason =
        if MapSet.member?(state.unavailable_actions, action.id) do
          "control_plane_unavailable"
        else
          "contact_ended"
        end

      publish_action_event(:contact_action_skipped, action, %{reason: reason}, acc)
      finalize_action(action, acc, :skipped)
    end)
  end

  defp gate_satisfied?(state, gate) do
    GateEngine.gate_satisfied?(state.gate_engine, gate)
  end

  defp publish_contact_ready(gate, details, state) do
    payload = %{
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      contact_id: state.contact_id,
      gate: to_string(gate),
      details: details || %{}
    }

    Phoenix.PubSub.broadcast(Cadence.PubSub, state.events_topic, {
      :contact_readiness,
      :contact_ready,
      payload
    })
  end

  defp publish_action_event(event_type, action, attrs, state) do
    payload =
      %{
        organization_id: state.organization_id,
        mission_id: state.mission_id,
        contact_id: action.contact_id,
        contact_action_id: action.id,
        gate: to_string(action.gate),
        command_ref: action.command_ref
      }
      |> Map.merge(attrs)

    Phoenix.PubSub.broadcast(Cadence.PubSub, state.events_topic, {
      :contact_action,
      event_type,
      payload
    })
  end

  defp normalize_error({code, message}) when is_binary(message) do
    {to_string(code), message}
  end

  defp normalize_error({code, _} = reason) do
    {to_string(code), inspect(reason)}
  end

  defp normalize_error(reason) do
    {to_string(reason), inspect(reason)}
  end

  defp find_action(actions, action_id) do
    Enum.find(actions, fn action -> action.id == action_id end)
  end

  defp via_tuple(mission_id, contact_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:contact_runtime, mission_id, contact_id}}}
  end
end
