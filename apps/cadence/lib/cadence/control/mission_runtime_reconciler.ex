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
  alias Cadence.Governance
  alias Cadence.Runtime.GenerationApplied
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions, as: RuntimeMissions

  @default_safety_poll_interval_ms 30_000

  def start_link(opts) when is_list(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, opts, name: MissionRuntime.reconciler_name(mission_id))
  end

  @spec apply_generation(binary(), BindingSetActivation.t(), BindingSet.t()) ::
          {:ok, GenerationApplied.t()} | {:error, term()}
  def apply_generation(
        mission_id,
        %BindingSetActivation{} = activation,
        %BindingSet{} = binding_set
      ) do
    GenServer.call(
      MissionRuntime.reconciler_name(mission_id),
      {:apply_generation, activation, binding_set},
      :infinity
    )
  end

  @spec reconcile(binary()) :: {:ok, GenerationApplied.t()} | {:error, term()}
  def reconcile(mission_id) when is_binary(mission_id) do
    GenServer.call(MissionRuntime.reconciler_name(mission_id), :reconcile, :infinity)
  end

  @spec snapshot(binary()) :: map()
  def snapshot(mission_id) when is_binary(mission_id) do
    GenServer.call(MissionRuntime.reconciler_name(mission_id), :snapshot)
  end

  @impl true
  def init(opts) do
    state = %{
      mission_id: Keyword.fetch!(opts, :mission_id),
      desired_generation: nil,
      applied_generation: nil,
      last_observation: nil,
      last_error: nil,
      safety_poll_interval_ms:
        Keyword.get(opts, :safety_poll_interval_ms, @default_safety_poll_interval_ms),
      safety_timer: nil
    }

    {:ok, state, {:continue, :reconcile}}
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
    {:reply, Map.drop(state, [:safety_timer]), state}
  end

  @impl true
  def handle_info(:safety_reconcile, state) do
    {_reply, state} = reconcile_state(%{state | safety_timer: nil})
    {:noreply, schedule_safety_poll(state)}
  end

  defp reconcile_state(state) do
    with {:ok, %BindingSetActivation{} = activation} <-
           Activations.fetch_active_basis_for_reconciliation(state.mission_id),
         {:ok, %BindingSet{} = binding_set} <- fetch_binding_set(activation) do
      apply_state(state, activation, binding_set)
    else
      {:error, :no_active_binding_set} = error ->
        {error, %{state | last_error: nil}}

      {:error, reason} = error ->
        {error, %{state | last_error: reason}}
    end
  end

  defp apply_state(state, activation, binding_set) do
    with :ok <- matching_mission(state.mission_id, activation.mission_id),
         {:ok, %MissionRuntimeSpec{} = runtime_spec} <- runtime_spec(activation, binding_set),
         {:ok, %GenerationApplied{} = observation} <- RuntimeMissions.apply(runtime_spec) do
      {{:ok, observation},
       %{
         state
         | desired_generation: activation.generation,
           applied_generation: observation.generation,
           last_observation: observation,
           last_error: nil
       }}
    else
      {:error, reason} = error ->
        {error,
         %{
           state
           | desired_generation: activation.generation,
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

  defp schedule_safety_poll(state) do
    if is_reference(state.safety_timer), do: Process.cancel_timer(state.safety_timer)

    %{
      state
      | safety_timer: Process.send_after(self(), :safety_reconcile, state.safety_poll_interval_ms)
    }
  end
end
