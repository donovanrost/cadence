defmodule Cadence.Commanding.Groups.Halt do
  @moduledoc """
  Stop on failure per target (DECISIONS #31): a group member must not release
  after an earlier member of the same target (same group, lower position)
  failed to release, failed or timed out verification, or was itself halted.
  Other targets continue. Checked at release time, so it also covers failures
  that happened while later members were already queued.
  """

  import Ecto.Query

  alias Cadence.Commanding.{CommandReleaseAttemptRow, CommandRequestRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @failed_verification ~w(failed timed_out)

  @doc "The id of an earlier failed member of the same target, or `nil`."
  @spec earlier_failure(struct()) :: binary() | nil
  def earlier_failure(%CommandRequestRow{command_group_id: nil}), do: nil

  def earlier_failure(%CommandRequestRow{} = row) do
    earlier =
      CommandRequestRow
      |> where(
        [r],
        r.organization_id == ^row.organization_id and r.mission_id == ^row.mission_id and
          r.command_group_id == ^row.command_group_id and
          r.group_target_index == ^row.group_target_index and
          r.group_position < ^row.group_position
      )
      |> order_by([r], asc: r.group_position)
      |> Repo.all()

    released_failures = release_failures(row, Enum.map(earlier, & &1.command_request_id))

    Enum.find_value(earlier, fn member ->
      if failed?(member, released_failures), do: member.command_request_id
    end)
  end

  defp failed?(member, released_failures) do
    member.verification_state in @failed_verification or
      MapSet.member?(released_failures, member.command_request_id) or
      halted?(member)
  end

  defp halted?(%{lifecycle_state: "canceled", metadata_document: document}) do
    case JsonDocument.unwrap_value(document) do
      %{"cancellation" => %{"reason" => "earlier_command_failed" <> _}} -> true
      _other -> false
    end
  end

  defp halted?(_member), do: false

  defp release_failures(_row, []), do: MapSet.new()

  defp release_failures(row, ids) do
    CommandReleaseAttemptRow
    |> where(
      [a],
      a.organization_id == ^row.organization_id and a.mission_id == ^row.mission_id and
        a.command_request_id in ^ids and a.lifecycle_state == "release_failed"
    )
    |> select([a], a.command_request_id)
    |> Repo.all()
    |> MapSet.new()
  end
end
