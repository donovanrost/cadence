defmodule Cadence.Commanding.VerifierWorkflow do
  @moduledoc """
  Coordinates command-verifier evaluation over injected persistence operations.
  """

  alias Cadence.Commanding.{
    CommandVerifierInstance,
    VerifierEvaluation,
    VerifierTransportSignals
  }

  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord}
  alias Cadence.Telemetry.Sample

  @type pending_entry :: {term(), CommandVerifierInstance.t()}
  @type fetch_pending :: (binary(), binary() -> [pending_entry()])
  @type fetch_pending_transport :: (binary(), binary(), [binary()] -> [pending_entry()])
  @type persist_updates :: ([pending_entry()] ->
                              {:ok, [CommandVerifierInstance.t()]} | {:error, term()})

  @spec evaluate_telemetry([Sample.t()], fetch_pending(), persist_updates()) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def evaluate_telemetry(telemetry_samples, fetch_pending, persist_updates)
      when is_list(telemetry_samples) and is_function(fetch_pending, 2) and
             is_function(persist_updates, 1) do
    telemetry_samples
    |> Enum.group_by(& &1.mission_id)
    |> Enum.reduce_while({:ok, []}, fn {mission_id, mission_samples}, {:ok, acc} ->
      case evaluate_telemetry_for_mission(
             mission_id,
             mission_samples,
             fetch_pending,
             persist_updates
           ) do
        {:ok, verifier_instances} ->
          {:cont, {:ok, acc ++ verifier_instances}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @spec evaluate_transport(
          [TransportCapabilityRecord.t()],
          [TransportActionRequest.t()],
          fetch_pending_transport(),
          persist_updates()
        ) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def evaluate_transport(
        transport_capability_records,
        transport_action_requests,
        fetch_pending,
        persist_updates
      )
      when is_list(transport_capability_records) and is_list(transport_action_requests) and
             is_function(fetch_pending, 3) and is_function(persist_updates, 1) do
    transport_capability_records
    |> VerifierTransportSignals.build(transport_action_requests)
    |> Enum.group_by(& &1.mission_id)
    |> Enum.reduce_while({:ok, []}, fn {mission_id, mission_transport_signals}, {:ok, acc} ->
      case evaluate_transport_for_mission(
             mission_id,
             mission_transport_signals,
             fetch_pending,
             persist_updates
           ) do
        {:ok, verifier_instances} ->
          {:cont, {:ok, acc ++ verifier_instances}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp evaluate_telemetry_for_mission(
         mission_id,
         telemetry_samples,
         fetch_pending,
         persist_updates
       )
       when is_binary(mission_id) and is_list(telemetry_samples) do
    case OrganizationScope.organization_id_for_mission(mission_id) do
      nil ->
        {:ok, []}

      organization_id ->
        sorted_samples =
          Enum.sort_by(telemetry_samples, &VerifierEvaluation.sample_sort_key/1, DateTime)

        organization_id
        |> fetch_pending.(mission_id)
        |> build_updates(fn %CommandVerifierInstance{} = verifier_instance ->
          VerifierEvaluation.evaluate_samples(verifier_instance, sorted_samples)
        end)
        |> persist_updates.()
    end
  end

  defp evaluate_transport_for_mission(
         mission_id,
         transport_signals,
         fetch_pending,
         persist_updates
       )
       when is_binary(mission_id) and is_list(transport_signals) do
    case OrganizationScope.organization_id_for_mission(mission_id) do
      nil ->
        {:ok, []}

      organization_id ->
        do_evaluate_transport_for_mission(
          organization_id,
          mission_id,
          transport_signals,
          fetch_pending,
          persist_updates
        )
    end
  end

  defp do_evaluate_transport_for_mission(
         organization_id,
         mission_id,
         transport_signals,
         fetch_pending,
         persist_updates
       ) do
    command_release_attempt_ids = transport_command_release_attempt_ids(transport_signals)

    if command_release_attempt_ids == [] do
      {:ok, []}
    else
      transport_signals_by_release_attempt_id =
        transport_signals
        |> Enum.sort_by(&VerifierEvaluation.transport_signal_sort_key/1)
        |> Enum.group_by(& &1.command_release_attempt_id)

      organization_id
      |> fetch_pending.(mission_id, command_release_attempt_ids)
      |> build_updates(fn %CommandVerifierInstance{} = verifier_instance ->
        relevant_signals =
          Map.get(
            transport_signals_by_release_attempt_id,
            verifier_instance.command_release_attempt_id,
            []
          )

        VerifierEvaluation.evaluate_transport_signals(verifier_instance, relevant_signals)
      end)
      |> persist_updates.()
    end
  end

  defp transport_command_release_attempt_ids(transport_signals) when is_list(transport_signals) do
    transport_signals
    |> Enum.map(& &1.command_release_attempt_id)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp build_updates(entries, evaluator)
       when is_list(entries) and is_function(evaluator, 1) do
    entries
    |> Enum.reduce([], fn {persistence_ref, %CommandVerifierInstance{} = verifier_instance},
                          acc ->
      case evaluator.(verifier_instance) do
        nil ->
          acc

        %CommandVerifierInstance{} = updated_instance ->
          [{persistence_ref, updated_instance} | acc]
      end
    end)
    |> Enum.reverse()
  end
end
