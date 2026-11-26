defmodule Cadence.Commanding.ApprovalDecisions do
  @moduledoc """
  #117 step 4b (P3; DECISIONS #112): a command request's decision rows as the four-eyes record
  (`Governance.DecisionRecord`), for the audits (#239). Each `command_approvals` row names:

  - **subject** `{kind: command_request, id, version: nil, digest}`: the request's review token at
    decision (a group member's own; a released request's at release);
  - **separated_from**: exactly the ids the separation check was given (the requester), `[]` for a
    `not_required` release (no check ran);
  - **admin_mode**: whether the decider (or releaser) acted as a platform admin.

  Newest first, at most 200 per call, with a `before` cursor (`{decided_at, command_approval_id}`, the
  previous page's last row).
  """

  @behaviour Cadence.Governance.DecisionRecord

  import Ecto.Query

  alias Cadence.Commanding.CommandApprovalRow
  alias Cadence.Governance.DecisionRecord
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @limit 200

  @impl true
  def decisions(organization_id, opts \\ []) do
    CommandApprovalRow
    |> where([row], row.organization_id == ^organization_id)
    |> before(Keyword.get(opts, :before))
    |> order_by([row], desc: row.decided_at, desc: row.command_approval_id)
    |> limit(^min(Keyword.get(opts, :limit, @limit), @limit))
    |> Repo.all()
    |> Enum.map(&record/1)
  end

  defp before(query, nil), do: query

  defp before(query, {%DateTime{} = at, id}) when is_binary(id),
    do:
      where(
        query,
        [row],
        row.decided_at < ^at or (row.decided_at == ^at and row.command_approval_id < ^id)
      )

  # The table's check allows exactly these (migration 20261121100000).
  defp decision("approved"), do: :approved
  defp decision("rejected"), do: :rejected
  defp decision("not_required"), do: :not_required

  defp record(%CommandApprovalRow{} = row) do
    %DecisionRecord{
      actor: JsonDocument.unwrap_value(row.decided_by_document),
      decision: decision(row.decision),
      reason: row.reason,
      decided_at: row.decided_at,
      subject: %{
        kind: "command_request",
        id: row.command_request_id,
        version: nil,
        digest: row.subject_digest,
        previous_digest: nil
      },
      policy: nil,
      admin_mode: row.admin_mode,
      separated_from: row.separated_from
    }
  end
end
