defmodule Cadence.Runtime.TransportRecords do
  @moduledoc """
  Data-plane persistence boundary for transport execution records and action requests.

  Callers receive runtime contracts and never depend on the Ecto row representation.
  """

  import Ecto.Query

  alias Cadence.Repo

  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord}

  alias Cadence.Runtime.TransportRecords.{
    TransportActionRequestRow,
    TransportCapabilityRecordRow
  }

  alias Ecto.Multi

  @spec add_capability_record_inserts(Multi.t(), [TransportCapabilityRecord.t()]) :: Multi.t()
  def add_capability_record_inserts(%Multi{} = multi, capability_records)
      when is_list(capability_records) do
    Enum.reduce(capability_records, multi, fn %TransportCapabilityRecord{} = capability_record,
                                              %Multi{} = acc ->
      Multi.insert(
        acc,
        {:transport_capability_record, capability_record.transport_record_id},
        TransportCapabilityRecordRow.changeset(capability_record)
      )
    end)
  end

  @spec add_action_request_inserts(Multi.t(), [TransportActionRequest.t()]) :: Multi.t()
  def add_action_request_inserts(%Multi{} = multi, action_requests)
      when is_list(action_requests) do
    Enum.reduce(action_requests, multi, fn %TransportActionRequest{} = action_request,
                                           %Multi{} = acc ->
      Multi.insert(
        acc,
        {:transport_action_request, action_request.action_request_id},
        TransportActionRequestRow.changeset(action_request)
      )
    end)
  end

  @spec for_command_release_attempt(module(), binary(), binary(), binary()) ::
          {[TransportCapabilityRecord.t()], [TransportActionRequest.t()]}
  def for_command_release_attempt(repo \\ Repo, organization_id, mission_id, release_attempt_id)
      when is_atom(repo) and is_binary(organization_id) and is_binary(mission_id) and
             is_binary(release_attempt_id) do
    capability_records =
      TransportCapabilityRecordRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          fragment(
            "? ->> 'command_release_attempt_id' = ?",
            row.metadata,
            ^release_attempt_id
          )
      )
      |> order_by([row], asc: row.recorded_at, asc: row.transport_record_id)
      |> repo.all()
      |> Enum.map(&TransportCapabilityRecordRow.to_domain/1)

    action_requests =
      TransportActionRequestRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_release_attempt_id == ^release_attempt_id
      )
      |> order_by([row], asc: row.requested_at, asc: row.action_request_id)
      |> repo.all()
      |> Enum.map(&TransportActionRequestRow.to_domain/1)

    {capability_records, action_requests}
  end
end
