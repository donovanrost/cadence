defmodule Cadence.Commanding.ReleaseStore do
  @moduledoc """
  Persists and retrieves command release attempts.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Commanding.{CommandReleaseAttempt, CommandReleaseAttemptRow}
  alias Cadence.Repo

  @spec persist(binary(), CommandReleaseAttempt.t()) ::
          {:ok, CommandReleaseAttempt.t()} | {:error, term()}
  def persist(organization_id, %CommandReleaseAttempt{} = command_release_attempt)
      when is_binary(organization_id) do
    with {:ok, scoped_command_release_attempt} <-
           put_organization_scope(command_release_attempt, organization_id),
         {:ok, %CommandReleaseAttemptRow{} = row} <-
           Repo.insert(CommandReleaseAttemptRow.changeset(scoped_command_release_attempt),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :command_release_attempt_id]
           ) do
      {:ok, CommandReleaseAttemptRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, CommandReleaseAttempt.t()} | {:error, term()}
  def fetch(organization_id, mission_id, command_release_attempt_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_release_attempt_id) do
    with {:ok, %CommandReleaseAttemptRow{} = row} <-
           fetch_row(organization_id, mission_id, command_release_attempt_id) do
      {:ok, CommandReleaseAttemptRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) :: [CommandReleaseAttempt.t()]
  def list(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandReleaseAttemptRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(:command_queue_entry_id, Keyword.get(opts, :command_queue_entry_id))
    |> maybe_filter_equals(:realized_contact_id, Keyword.get(opts, :realized_contact_id))
    |> maybe_filter_equals(:lifecycle_state, normalized_filter(opts, :lifecycle_state))
    |> order_by([row], asc: row.attempted_at, asc: row.command_release_attempt_id)
    |> Repo.all()
    |> Enum.map(&CommandReleaseAttemptRow.to_domain/1)
  end

  @spec fetch_row(binary(), binary(), binary()) :: {:ok, struct()} | {:error, term()}
  def fetch_row(organization_id, mission_id, command_release_attempt_id) do
    fetch_row(Repo, organization_id, mission_id, command_release_attempt_id)
  end

  @spec fetch_row(module(), binary(), binary(), binary()) ::
          {:ok, struct()} | {:error, term()}
  def fetch_row(repo, organization_id, mission_id, command_release_attempt_id) do
    case repo.get_by(CommandReleaseAttemptRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_release_attempt_id: command_release_attempt_id
         ) do
      nil -> {:error, :command_release_attempt_not_found}
      %CommandReleaseAttemptRow{} = row -> {:ok, row}
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

  defp maybe_filter_equals(query, field, value) when is_atom(value) do
    where(query, [row], field(row, ^field) == ^Atom.to_string(value))
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp put_organization_scope(%CommandReleaseAttempt{} = command_release_attempt, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case command_release_attempt.organization_id do
      nil ->
        {:ok, %CommandReleaseAttempt{command_release_attempt | organization_id: organization_id}}

      ^organization_id ->
        {:ok, command_release_attempt}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          command_release_attempt.mission_id}}
    end
  end
end
