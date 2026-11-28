defmodule Cadence.Commanding.RequestStore do
  @moduledoc """
  Reads of command requests and approval decisions. A request is written only as a command
  group's member (`Groups.GroupStore`).
  """

  import Ecto.Query

  alias Cadence.Commanding.{
    CommandApproval,
    CommandApprovalRow,
    CommandRequest,
    CommandRequestRow
  }

  alias Cadence.Repo

  @spec fetch_request(binary(), binary(), binary()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def fetch_request(organization_id, mission_id, command_request_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_request_id) do
    with {:ok, %CommandRequestRow{} = row} <-
           fetch_request_row(organization_id, mission_id, command_request_id) do
      {:ok, CommandRequestRow.to_domain(row)}
    end
  end

  @spec list_requests(binary(), binary(), keyword()) :: [CommandRequest.t()]
  def list_requests(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandRequestRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:lifecycle_state, normalized_filter(opts, :lifecycle_state))
    |> maybe_filter_in(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_refs))
    |> order_by([row], asc: row.requested_at, asc: row.command_request_id)
    |> Repo.all()
    |> Enum.map(&CommandRequestRow.to_domain/1)
  end

  @spec fetch_approval(binary(), binary(), binary()) ::
          {:ok, CommandApproval.t()} | {:error, term()}
  def fetch_approval(organization_id, mission_id, command_approval_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_approval_id) do
    case Repo.get_by(CommandApprovalRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_approval_id: command_approval_id
         ) do
      nil -> {:error, :command_approval_not_found}
      # #117 step 4b (api-ops on #639): a release's not_required record isn't an approval a
      # read shows; it's the four-eyes record's (ApprovalDecisions), and the audit's with #239.
      %CommandApprovalRow{decision: "not_required"} -> {:error, :command_approval_not_found}
      %CommandApprovalRow{} = row -> {:ok, CommandApprovalRow.to_domain(row)}
    end
  end

  @spec list_approvals(binary(), binary(), keyword()) :: [CommandApproval.t()]
  def list_approvals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandApprovalRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.decision != "not_required"
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(:decision, normalized_filter(opts, :decision))
    |> order_by([row], asc: row.decided_at, asc: row.command_approval_id)
    |> Repo.all()
    |> Enum.map(&CommandApprovalRow.to_domain/1)
  end

  @doc false
  @spec fetch_request_row(binary(), binary(), binary()) :: {:ok, struct()} | {:error, term()}
  def fetch_request_row(organization_id, mission_id, command_request_id) do
    case Repo.get_by(CommandRequestRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_request_id: command_request_id
         ) do
      nil -> {:error, :command_request_not_found}
      %CommandRequestRow{} = row -> {:ok, row}
    end
  end

  defp normalized_filter(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
    end
  end

  # `field IN (...)` for a list filter (one parameter, whatever its length); nil is no filter.
  defp maybe_filter_in(query, _field, nil), do: query

  defp maybe_filter_in(query, field, values) when is_list(values) do
    values = Enum.map(values, &if(is_atom(&1), do: Atom.to_string(&1), else: &1))
    where(query, [row], field(row, ^field) in ^values)
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, value) when is_atom(value) do
    where(query, [row], field(row, ^field) == ^Atom.to_string(value))
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end
end
