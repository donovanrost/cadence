defmodule Cadence.Commanding.VerifierStore do
  @moduledoc """
  Persists command-verifier instances and request/release verification rollups.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Commanding.{
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstance,
    CommandVerifierInstanceRow
  }

  alias Cadence.Repo

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, CommandVerifierInstance.t()} | {:error, term()}
  def fetch(organization_id, mission_id, command_verifier_instance_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_verifier_instance_id) do
    case Repo.get_by(CommandVerifierInstanceRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_verifier_instance_id: command_verifier_instance_id
         ) do
      nil -> {:error, :command_verifier_instance_not_found}
      %CommandVerifierInstanceRow{} = row -> {:ok, CommandVerifierInstanceRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) :: [CommandVerifierInstance.t()]
  def list(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandVerifierInstanceRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(
      :command_release_attempt_id,
      Keyword.get(opts, :command_release_attempt_id)
    )
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:phase, normalized_filter(opts, :phase))
    |> maybe_filter_equals(:lifecycle_state, normalized_filter(opts, :lifecycle_state))
    |> order_by([row], asc: row.inserted_at, asc: row.command_verifier_instance_id)
    |> Repo.all()
    |> Enum.map(&CommandVerifierInstanceRow.to_domain/1)
  end

  @spec timeout_projection() :: [CommandVerifierInstance.t()]
  def timeout_projection do
    pending_timeout_query()
    |> Repo.all()
    |> Enum.map(&CommandVerifierInstanceRow.to_domain/1)
  end

  @spec timeout(module(), DateTime.t()) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def timeout(repo, %DateTime{} = current_time) do
    timed_out_rows =
      pending_timeout_query()
      |> where([row], row.timeout_at <= ^current_time)
      |> order_by([row], asc: row.timeout_at, asc: row.command_verifier_instance_id)
      |> repo.all()

    apply_updates(
      repo,
      Enum.map(timed_out_rows, fn %CommandVerifierInstanceRow{} = row ->
        command_verifier_instance =
          row
          |> CommandVerifierInstanceRow.to_domain()
          |> Map.put(:lifecycle_state, :timed_out)
          |> Map.put(:failure_reason, "timed_out")

        {row, command_verifier_instance}
      end)
    )
  end

  @spec pending_timeout_instances(module(), binary(), binary(), binary()) :: [
          CommandVerifierInstance.t()
        ]
  def pending_timeout_instances(
        repo,
        organization_id,
        mission_id,
        command_release_attempt_id
      ) do
    CommandVerifierInstanceRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> where([row], row.command_release_attempt_id == ^command_release_attempt_id)
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], not is_nil(row.timeout_at))
    |> order_by([row], asc: row.timeout_at, asc: row.command_verifier_instance_id)
    |> repo.all()
    |> Enum.map(&CommandVerifierInstanceRow.to_domain/1)
  end

  @spec pending_entries(module(), binary(), binary()) :: [
          {struct(), CommandVerifierInstance.t()}
        ]
  def pending_entries(repo, organization_id, mission_id) do
    CommandVerifierInstanceRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> where([row], row.lifecycle_state == "pending")
    |> order_by([row], asc: row.inserted_at, asc: row.command_verifier_instance_id)
    |> repo.all()
    |> Enum.map(fn %CommandVerifierInstanceRow{} = row ->
      {row, CommandVerifierInstanceRow.to_domain(row)}
    end)
  end

  @spec pending_transport_entries(module(), binary(), binary(), [binary()]) :: [
          {struct(), CommandVerifierInstance.t()}
        ]
  def pending_transport_entries(
        repo,
        organization_id,
        mission_id,
        command_release_attempt_ids
      ) do
    CommandVerifierInstanceRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], row.command_release_attempt_id in ^command_release_attempt_ids)
    |> order_by([row], asc: row.inserted_at, asc: row.command_verifier_instance_id)
    |> repo.all()
    |> Enum.map(fn %CommandVerifierInstanceRow{} = row ->
      {row, CommandVerifierInstanceRow.to_domain(row)}
    end)
  end

  @spec add_inserts(Multi.t(), [CommandVerifierInstance.t()]) :: Multi.t()
  def add_inserts(%Multi{} = multi, verifier_instances) when is_list(verifier_instances) do
    Enum.reduce(verifier_instances, multi, fn %CommandVerifierInstance{} = verifier_instance,
                                              %Multi{} = acc ->
      Multi.insert(
        acc,
        {:command_verifier_instance, verifier_instance.command_verifier_instance_id},
        CommandVerifierInstanceRow.changeset(verifier_instance)
      )
    end)
  end

  @spec apply_updates(module(), [{struct(), CommandVerifierInstance.t()}]) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def apply_updates(_repo, []), do: {:ok, []}

  def apply_updates(repo, verifier_updates) when is_list(verifier_updates) do
    affected_rollups =
      verifier_updates
      |> Enum.map(fn {%CommandVerifierInstanceRow{} = row, _updated_instance} ->
        {row.organization_id, row.mission_id, row.command_request_id,
         row.command_release_attempt_id}
      end)
      |> Enum.uniq()

    with {:ok, updated_rows} <- update_rows(repo, verifier_updates),
         {:ok, _rollups} <- recompute_rollups(repo, affected_rollups) do
      {:ok, Enum.map(updated_rows, &CommandVerifierInstanceRow.to_domain/1)}
    end
  end

  defp pending_timeout_query do
    CommandVerifierInstanceRow
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], not is_nil(row.timeout_at))
    |> order_by([row], asc: row.timeout_at, asc: row.command_verifier_instance_id)
  end

  defp update_rows(repo, verifier_updates) when is_list(verifier_updates) do
    Enum.reduce_while(verifier_updates, {:ok, []}, fn
      {%CommandVerifierInstanceRow{} = row, %CommandVerifierInstance{} = updated_instance},
      {:ok, acc} ->
        case repo.update(CommandVerifierInstanceRow.update_changeset(row, updated_instance)) do
          {:ok, updated_row} -> {:cont, {:ok, [updated_row | acc]}}
          {:error, %Changeset{} = changeset} -> {:halt, {:error, changeset}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
    |> case do
      {:ok, updated_rows} -> {:ok, Enum.reverse(updated_rows)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp recompute_rollups(repo, affected_rollups) when is_list(affected_rollups) do
    Enum.reduce_while(affected_rollups, {:ok, []}, fn
      {organization_id, mission_id, command_request_id, command_release_attempt_id}, {:ok, acc} ->
        verifier_rows =
          CommandVerifierInstanceRow
          |> where(
            [row],
            row.organization_id == ^organization_id and row.mission_id == ^mission_id and
              row.command_request_id == ^command_request_id and
              row.command_release_attempt_id == ^command_release_attempt_id
          )
          |> order_by([row], asc: row.inserted_at, asc: row.command_verifier_instance_id)
          |> repo.all()

        verification_state = aggregate_state(verifier_rows)
        verification_state_string = Atom.to_string(verification_state)

        with %CommandRequestRow{} = command_request_row <-
               repo.get_by(CommandRequestRow,
                 organization_id: organization_id,
                 mission_id: mission_id,
                 command_request_id: command_request_id
               ),
             %CommandReleaseAttemptRow{} = command_release_attempt_row <-
               repo.get_by(CommandReleaseAttemptRow,
                 organization_id: organization_id,
                 mission_id: mission_id,
                 command_release_attempt_id: command_release_attempt_id
               ),
             {:ok, updated_request_row} <-
               maybe_update_request_verification_state(
                 repo,
                 command_request_row,
                 verification_state_string
               ),
             {:ok, updated_release_attempt_row} <-
               maybe_update_release_attempt_verification_state(
                 repo,
                 command_release_attempt_row,
                 verification_state_string
               ) do
          {:cont,
           {:ok,
            [
              {updated_request_row.command_request_id,
               updated_release_attempt_row.command_release_attempt_id}
              | acc
            ]}}
        else
          nil ->
            {:halt, {:error, :command_verification_rollup_target_not_found}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
    end)
  end

  defp maybe_update_request_verification_state(
         repo,
         %CommandRequestRow{} = command_request_row,
         verification_state_string
       ) do
    if command_request_row.verification_state == verification_state_string do
      {:ok, command_request_row}
    else
      command_request_row
      |> CommandRequestRow.verification_state_changeset(
        verification_state_string && String.to_existing_atom(verification_state_string)
      )
      |> repo.update()
    end
  rescue
    ArgumentError ->
      {:error, :invalid_command_request_verification_state}
  end

  defp maybe_update_release_attempt_verification_state(
         repo,
         %CommandReleaseAttemptRow{} = command_release_attempt_row,
         verification_state_string
       ) do
    if command_release_attempt_row.verification_state == verification_state_string do
      {:ok, command_release_attempt_row}
    else
      command_release_attempt_row
      |> CommandReleaseAttemptRow.verification_state_changeset(
        verification_state_string && String.to_existing_atom(verification_state_string)
      )
      |> repo.update()
    end
  rescue
    ArgumentError ->
      {:error, :invalid_command_release_attempt_verification_state}
  end

  defp aggregate_state([]), do: :not_required

  defp aggregate_state(verifier_rows) when is_list(verifier_rows) do
    lifecycle_states =
      Enum.map(verifier_rows, fn %CommandVerifierInstanceRow{} = row ->
        row.lifecycle_state
      end)

    cond do
      Enum.any?(lifecycle_states, &(&1 == "failed")) ->
        :failed

      Enum.any?(lifecycle_states, &(&1 == "timed_out")) ->
        :timed_out

      Enum.all?(lifecycle_states, &(&1 == "satisfied")) ->
        :satisfied

      true ->
        :pending
    end
  end

  defp normalized_filter(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
    end
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end
end
