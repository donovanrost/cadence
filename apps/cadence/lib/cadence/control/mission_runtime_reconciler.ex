defmodule Cadence.Control.MissionRuntimeReconciler do
  @moduledoc """
  Mission control owner that converges durable active-basis generations into
  the data plane.
  """

  use GenServer

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Control.Activations
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Control.MissionRuntime
  alias Cadence.Control.ProcessNamespace
  alias Cadence.Governance
  alias Cadence.Runtime.GenerationApplied
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions, as: RuntimeMissions
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace

  @default_safety_poll_interval_ms 30_000

  def start_link(opts) when is_list(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    process_namespace = process_namespace(opts)

    GenServer.start_link(__MODULE__, opts,
      name: MissionRuntime.reconciler_name(process_namespace, mission_id)
    )
  end

  @spec apply_generation(binary(), BindingSetActivation.t(), BindingSet.t()) ::
          {:ok, GenerationApplied.t()} | {:error, term()}
  def apply_generation(
        mission_id,
        %BindingSetActivation{} = activation,
        %BindingSet{} = binding_set
      ) do
    apply_generation(ProcessNamespace.default(), mission_id, activation, binding_set)
  end

  @spec apply_generation(
          ProcessNamespace.t(),
          binary(),
          BindingSetActivation.t(),
          BindingSet.t()
        ) :: {:ok, GenerationApplied.t()} | {:error, term()}
  def apply_generation(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        %BindingSetActivation{} = activation,
        %BindingSet{} = binding_set
      ) do
    GenServer.call(
      MissionRuntime.reconciler_name(process_namespace, mission_id),
      {:apply_generation, activation, binding_set},
      :infinity
    )
  end

  @spec reconcile(binary()) :: {:ok, GenerationApplied.t()} | {:error, term()}
  def reconcile(mission_id) when is_binary(mission_id),
    do: reconcile(ProcessNamespace.default(), mission_id)

  @spec reconcile(ProcessNamespace.t(), binary()) ::
          {:ok, GenerationApplied.t()} | {:error, term()}
  def reconcile(%ProcessNamespace{} = process_namespace, mission_id) when is_binary(mission_id) do
    GenServer.call(
      MissionRuntime.reconciler_name(process_namespace, mission_id),
      :reconcile,
      :infinity
    )
  end

  @spec snapshot(binary()) :: map()
  def snapshot(mission_id) when is_binary(mission_id),
    do: snapshot(ProcessNamespace.default(), mission_id)

  @spec snapshot(ProcessNamespace.t(), binary()) :: map()
  def snapshot(%ProcessNamespace{} = process_namespace, mission_id) when is_binary(mission_id) do
    GenServer.call(MissionRuntime.reconciler_name(process_namespace, mission_id), :snapshot)
  end

  @doc """
  Waits until all reconciliation work sent before this call has settled.

  The periodic safety timer may remain scheduled.
  """
  @spec await_settled(binary()) :: {:ok, map()} | {:error, :noproc}
  def await_settled(mission_id) when is_binary(mission_id),
    do: await_settled(ProcessNamespace.default(), mission_id)

  @spec await_settled(ProcessNamespace.t(), binary()) :: {:ok, map()} | {:error, :noproc}
  def await_settled(%ProcessNamespace{} = process_namespace, mission_id)
      when is_binary(mission_id) do
    {:ok,
     GenServer.call(
       MissionRuntime.reconciler_name(process_namespace, mission_id),
       :await_settled,
       :infinity
     )}
  catch
    :exit, {:noproc, _details} -> {:error, :noproc}
    :exit, {:normal, _details} -> {:error, :noproc}
  end

  @impl true
  def code_change(_old_version, state, _extra),
    do: {:ok, Map.put(state, :applied_basis, nil)}

  @impl true
  def init(opts) do
    state = %{
      mission_id: Keyword.fetch!(opts, :mission_id),
      process_namespace: process_namespace(opts),
      runtime_process_namespace: runtime_process_namespace(opts),
      desired_generation: nil,
      applied_generation: nil,
      last_observation: nil,
      last_error: nil,
      applied_basis: nil,
      safety_poll_interval_ms:
        Keyword.get(opts, :safety_poll_interval_ms, @default_safety_poll_interval_ms),
      safety_poll?: Keyword.get(opts, :safety_poll?, true),
      safety_timer: nil
    }

    if Keyword.get(opts, :reconcile_on_start?, true) do
      {:ok, state, {:continue, :reconcile}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:reconcile, state) do
    {_reply, state} = reconcile_state(state)
    {:noreply, schedule_safety_poll(state)}
  end

  @impl true
  def handle_call(
        {:apply_generation, %BindingSetActivation{} = activation, %BindingSet{} = binding_set},
        _from,
        state
      ) do
    {reply, state} = apply_state(state, activation, binding_set)
    {:reply, reply, state}
  end

  def handle_call(:reconcile, _from, state) do
    {reply, state} = reconcile_state(state)
    {:reply, reply, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_from_state(state), state}
  end

  def handle_call(:await_settled, _from, state) do
    {:reply, snapshot_from_state(state), state}
  end

  @impl true
  def handle_info(:safety_reconcile, state) do
    {_reply, state} = reconcile_state(%{state | safety_timer: nil})
    {:noreply, schedule_safety_poll(state)}
  end

  defp reconcile_state(state) do
    case Activations.fetch_active_identity_for_reconciliation(state.mission_id) do
      {:ok, identity} ->
        case confirm_unchanged(state, identity) do
          {:ok, observation} ->
            {{:ok, observation}, %{state | last_observation: observation, last_error: nil}}

          :rebuild ->
            materialize_and_apply(state)
        end

      {:error, reason} = error ->
        reconciliation_error(state, error, reason)
    end
  end

  defp confirm_unchanged(%{applied_basis: %{durable: identity, runtime: guard}} = state, identity) do
    if MissionRuntimeSpec.reconciliation_guard_current?(guard) do
      case RuntimeMissions.confirm_applied(
             state.runtime_process_namespace,
             state.mission_id,
             guard.identity
           ) do
        {:ok, observation} -> {:ok, observation}
        _other -> :rebuild
      end
    else
      :rebuild
    end
  end

  defp confirm_unchanged(_state, _identity), do: :rebuild

  defp materialize_and_apply(state) do
    with {:ok, %BindingSetActivation{} = activation} <-
           Activations.fetch_active_basis_for_reconciliation(state.mission_id),
         {:ok, %BindingSet{} = binding_set} <- fetch_binding_set(activation) do
      apply_state(state, activation, binding_set)
    else
      {:error, reason} = error -> reconciliation_error(state, error, reason)
    end
  end

  defp reconciliation_error(state, error, reason) do
    last_error = if reason == :no_active_binding_set, do: nil, else: reason
    {error, %{state | last_error: last_error, applied_basis: nil}}
  end

  defp apply_state(state, activation, binding_set) do
    with :ok <- matching_mission(state.mission_id, activation.mission_id),
         {:ok, %MissionRuntimeSpec{} = runtime_spec} <- runtime_spec(activation, binding_set),
         {:ok, %GenerationApplied{} = observation} <-
           RuntimeMissions.apply(state.runtime_process_namespace, runtime_spec) do
      {{:ok, observation},
       %{
         state
         | desired_generation: activation.generation,
           applied_generation: observation.generation,
           last_observation: observation,
           last_error: nil,
           applied_basis: %{
             durable: BindingSetActivation.identity(activation),
             runtime: MissionRuntimeSpec.reconciliation_guard(runtime_spec)
           }
       }}
    else
      {:error, reason} = error ->
        {error,
         %{
           state
           | desired_generation: activation.generation,
             applied_basis: nil,
             last_error: reason
         }}
    end
  end

  defp fetch_binding_set(%BindingSetActivation{organization_id: nil} = activation) do
    Governance.fetch_binding_set(
      activation.mission_id,
      activation.binding_set_id,
      activation.binding_set_version
    )
  end

  defp fetch_binding_set(%BindingSetActivation{} = activation) do
    Governance.fetch_binding_set(
      activation.organization_id,
      activation.mission_id,
      activation.binding_set_id,
      activation.binding_set_version
    )
  end

  defp runtime_spec(activation, binding_set) do
    with {:ok, mission_model_basis} <- MissionModelPromotion.runtime_basis(activation) do
      %{
        activation_id: activation.activation_id,
        activation_request_id: activation.activation_request_id,
        organization_id: activation.organization_id,
        mission_id: activation.mission_id,
        generation: activation.generation,
        binding_set_id: activation.binding_set_id,
        binding_set_version: activation.binding_set_version,
        binding_set_content_sha256: activation.binding_set_content_sha256,
        binding_set: binding_set,
        activated_at: activation.activated_at,
        metadata: activation.metadata
      }
      |> Map.merge(mission_model_basis)
      |> MissionRuntimeSpec.new()
    end
  end

  defp matching_mission(mission_id, mission_id), do: :ok
  defp matching_mission(_mission_id, _other), do: {:error, :activation_mission_mismatch}

  defp schedule_safety_poll(%{safety_poll?: false} = state), do: state

  defp schedule_safety_poll(state) do
    if is_reference(state.safety_timer), do: Process.cancel_timer(state.safety_timer)

    %{
      state
      | safety_timer: Process.send_after(self(), :safety_reconcile, state.safety_poll_interval_ms)
    }
  end

  defp snapshot_from_state(state) do
    state
    |> Map.drop([
      :process_namespace,
      :runtime_process_namespace,
      :applied_basis,
      :safety_poll?,
      :safety_timer
    ])
    |> Map.put(:status, :settled)
    |> Map.put(:safety_timer_scheduled?, is_reference(state.safety_timer))
  end

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end

  defp runtime_process_namespace(opts) do
    Keyword.get_lazy(
      opts,
      :runtime_process_namespace,
      &RuntimeProcessNamespace.default/0
    )
  end
end
