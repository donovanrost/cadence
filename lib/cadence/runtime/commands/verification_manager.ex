defmodule Cadence.Runtime.Commands.VerificationManager do
  @moduledoc """
  Mission-scoped manager for command verification.

  Owns the telemetry subscription and tracks per-command verification runners.
  """

  use GenServer
  require Logger

  alias Cadence.Commands.VerificationRunner
  alias Cadence.Recordings
  alias Cadence.Recordings.Recordables.{CommandVerificationFailed, CommandVerified}
  alias Cadence.Time, as: CadenceTime

  defmodule PendingVerification do
    @moduledoc false
    defstruct [
      :aggregate_id,
      :recording_id,
      :target_id,
      :organization_id,
      :bucket_id,
      :runner
    ]
  end

  defmodule State do
    @moduledoc false
    defstruct [:mission_id, pending: %{}]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  def whereis(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, {:command_verification, mission_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:command_verification, mission_id}}}
  end

  def start_verification(mission_id, attrs) when is_map(attrs) do
    case whereis(mission_id) do
      nil -> {:error, :verification_manager_not_running}
      pid -> GenServer.call(pid, {:start_verification, attrs})
    end
  end

  def cancel_verification(mission_id, target_id, aggregate_id) do
    case whereis(mission_id) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:cancel_verification, target_id, aggregate_id})
    end
  end

  def verification_status(mission_id, target_id, aggregate_id) do
    case whereis(mission_id) do
      nil -> :not_found
      pid -> GenServer.call(pid, {:verification_status, target_id, aggregate_id})
    end
  end

  def pending_count(mission_id, target_id) do
    case whereis(mission_id) do
      nil -> 0
      pid -> GenServer.call(pid, {:pending_count, target_id})
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(mission_id) when is_binary(mission_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:telemetry")
    {:ok, %State{mission_id: mission_id}}
  end

  @impl true
  def handle_call({:start_verification, attrs}, _from, state) do
    with {:ok, pending} <- build_pending(state, attrs),
         {:ok, runner} <-
           VerificationRunner.new(
             pending.aggregate_id,
             state.mission_id,
             pending.target_id,
             attrs.verifiers
           ),
         {:ok, runner} <- start_runner(runner) do
      updated_pending = %{pending | runner: runner}
      pending_map = Map.put(state.pending, pending.aggregate_id, updated_pending)
      {:reply, :ok, %{state | pending: pending_map}}
    else
      {:error, :no_verifiers} ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      :complete ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:verification_status, target_id, aggregate_id}, _from, state) do
    case Map.get(state.pending, aggregate_id) do
      %PendingVerification{target_id: ^target_id, runner: runner} ->
        {:reply, {:pending, %{stage: VerificationRunner.current_stage(runner)}}, state}

      _ ->
        {:reply, :not_found, state}
    end
  end

  def handle_call({:pending_count, target_id}, _from, state) do
    count =
      state.pending
      |> Map.values()
      |> Enum.count(&(&1.target_id == target_id))

    {:reply, count, state}
  end

  @impl true
  def handle_cast({:cancel_verification, target_id, aggregate_id}, state) do
    case Map.get(state.pending, aggregate_id) do
      %PendingVerification{target_id: ^target_id, runner: runner} ->
        _ = VerificationRunner.cancel_timeout(runner)
        {:noreply, %{state | pending: Map.delete(state.pending, aggregate_id)}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:verification_stage_timeout, aggregate_id, stage}, state) do
    case Map.get(state.pending, aggregate_id) do
      nil ->
        {:noreply, state}

      %PendingVerification{runner: runner} = pending ->
        handle_stage_timeout(state, pending, runner, stage)
    end
  end

  def handle_info(
        {:telemetry_update, target_id, packet_name, item_name, telemetry_value},
        state
      ) do
    updated_state =
      Enum.reduce(state.pending, state, fn {aggregate_id, pending}, acc ->
        if pending.target_id == target_id do
          apply_update(acc, aggregate_id, pending, packet_name, item_name, telemetry_value.value)
        else
          acc
        end
      end)

    {:noreply, updated_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Verification Helpers
  # ---------------------------------------------------------------------------

  defp build_pending(%State{} = state, attrs) do
    required = [
      :aggregate_id,
      :recording_id,
      :target_id,
      :organization_id,
      :bucket_id,
      :verifiers
    ]

    missing =
      required
      |> Enum.reject(&Map.has_key?(attrs, &1))

    if missing == [] and is_list(attrs.verifiers) do
      pending = %PendingVerification{
        aggregate_id: attrs.aggregate_id,
        recording_id: attrs.recording_id,
        target_id: attrs.target_id,
        organization_id: attrs.organization_id,
        bucket_id: attrs.bucket_id
      }

      if Map.has_key?(state.pending, pending.aggregate_id) do
        {:error, :already_pending}
      else
        {:ok, pending}
      end
    else
      error =
        if missing == [] do
          {:error, :invalid_verifiers}
        else
          {:error, {:missing_attrs, missing}}
        end

      error
    end
  end

  defp start_runner(runner) do
    case VerificationRunner.start_current_stage(runner) do
      {:ok, runner} ->
        runner = VerificationRunner.start_timeout(runner, self())

        Logger.info(
          "Starting verification for aggregate_id=#{runner.command_log_id}, " <>
            "stage=#{VerificationRunner.current_stage(runner)}"
        )

        {:ok, runner}

      {:complete, _runner} ->
        Logger.warning("Verification completed immediately with no stages")
        :complete
    end
  end

  defp apply_update(state, aggregate_id, pending, packet_name, item_name, value) do
    case VerificationRunner.check_update(pending.runner, packet_name, item_name, value) do
      {:stage_complete, updated_runner} ->
        Logger.info(
          "Verification stage #{VerificationRunner.current_stage(pending.runner)} complete for " <>
            "aggregate_id=#{aggregate_id}, advancing to next stage"
        )

        case VerificationRunner.start_current_stage(updated_runner) do
          {:ok, runner_with_stage} ->
            runner_with_timeout = VerificationRunner.start_timeout(runner_with_stage, self())
            updated_pending = %{pending | runner: runner_with_timeout}
            put_pending(state, aggregate_id, updated_pending)

          {:complete, final_runner} ->
            complete_verification(state, aggregate_id, pending, final_runner)
        end

      {:all_complete, final_runner} ->
        complete_verification(state, aggregate_id, pending, final_runner)

      {:failed, _runner, reason} ->
        Logger.warning("Verification failed for aggregate_id=#{aggregate_id}: #{inspect(reason)}")
        record_verification_failed(pending, aggregate_id, %{error_reason: inspect(reason)})
        drop_pending(state, aggregate_id)

      {:pending, updated_runner} ->
        updated_pending = %{pending | runner: updated_runner}
        put_pending(state, aggregate_id, updated_pending)
    end
  end

  defp handle_stage_timeout(state, pending, runner, stage) do
    if VerificationRunner.current_stage(runner) == stage do
      handle_timeout_action(
        state,
        pending,
        VerificationRunner.handle_timeout(runner)
      )
    else
      {:noreply, state}
    end
  end

  defp handle_timeout_action(state, pending, {:continue, updated_runner}) do
    case VerificationRunner.start_current_stage(updated_runner) do
      {:ok, runner_with_stage} ->
        runner_with_timeout = VerificationRunner.start_timeout(runner_with_stage, self())
        updated_pending = %{pending | runner: runner_with_timeout}
        {:noreply, put_pending(state, pending.aggregate_id, updated_pending)}

      {:complete, final_runner} ->
        {:noreply, complete_verification(state, pending.aggregate_id, pending, final_runner)}
    end
  end

  defp handle_timeout_action(state, pending, {:retry, updated_runner}) do
    runner_with_timeout = VerificationRunner.start_timeout(updated_runner, self())
    updated_pending = %{pending | runner: runner_with_timeout}
    {:noreply, put_pending(state, pending.aggregate_id, updated_pending)}
  end

  defp handle_timeout_action(state, pending, {:abort, _runner}) do
    Logger.warning(
      "Verification aborted for aggregate_id=#{pending.aggregate_id}, " <>
        "stage=#{VerificationRunner.current_stage(pending.runner)}"
    )

    record_verification_failed(pending, pending.aggregate_id, %{
      error_reason:
        "Verification stage #{VerificationRunner.current_stage(pending.runner)} timeout"
    })

    {:noreply, drop_pending(state, pending.aggregate_id)}
  end

  defp complete_verification(state, aggregate_id, pending, runner) do
    Logger.info(
      "All verification stages complete for aggregate_id=#{aggregate_id}, " <>
        "stages: #{inspect(VerificationRunner.completed_stages(runner))}"
    )

    record_verified(pending, aggregate_id, %{
      stages_completed: Enum.map(VerificationRunner.completed_stages(runner), &to_string/1)
    })

    drop_pending(state, aggregate_id)
  end

  # ---------------------------------------------------------------------------
  # Pending Map Helpers
  # ---------------------------------------------------------------------------

  defp put_pending(state, aggregate_id, pending) do
    %{state | pending: Map.put(state.pending, aggregate_id, pending)}
  end

  defp drop_pending(state, aggregate_id) do
    %{state | pending: Map.delete(state.pending, aggregate_id)}
  end

  # ---------------------------------------------------------------------------
  # Recording Helpers
  # ---------------------------------------------------------------------------

  defp record_verified(pending, aggregate_id, verification_result) do
    now = CadenceTime.now()

    recordable_attrs = %{
      verification_item: verification_result[:item],
      verification_expected: verification_result[:expected],
      verification_actual: verification_result[:actual],
      verification_result: verification_result[:result],
      stages_completed: verification_result[:stages_completed] || []
    }

    recording_attrs = %{
      organization_id: pending.organization_id,
      bucket_id: pending.bucket_id,
      aggregate_id: aggregate_id,
      parent_id: pending.recording_id,
      root_id: aggregate_id,
      actor_type: "system",
      timestamp: now
    }

    Recordings.create(CommandVerified, recordable_attrs, recording_attrs)
  end

  defp record_verification_failed(pending, aggregate_id, error_info) do
    now = CadenceTime.now()

    recordable_attrs = %{
      error_reason: error_info[:error_reason],
      verification_actual: error_info[:actual],
      verification_expected: error_info[:expected]
    }

    recording_attrs = %{
      organization_id: pending.organization_id,
      bucket_id: pending.bucket_id,
      aggregate_id: aggregate_id,
      parent_id: pending.recording_id,
      root_id: aggregate_id,
      actor_type: "system",
      timestamp: now
    }

    Recordings.create(CommandVerificationFailed, recordable_attrs, recording_attrs)
  end
end
