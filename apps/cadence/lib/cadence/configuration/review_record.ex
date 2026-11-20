defmodule Cadence.Configuration.ReviewRecord do
  @moduledoc """
  #117 step 2 (P3; var/four-eyes-record-design.md; DECISIONS #112): a change set's decision row is
  a complete four-eyes record. Every row (a reviewer's `approved` or `sent_back`, or a direct
  apply's `not_required`) names:

  - **subject** `{kind: change_set, id, version, digest}`: `digest/1` over the staged ops it
    decided. The apply recomputes it from the ops it runs and refuses on a mismatch, so approved
    equals applied, provably from the row.
  - **policy**: the approval policy in force (the set's `policy_document`).
  - **separated_from**: exactly the actor ids the separation check compared (the submitter and
    every change's author, services by their own id), sorted and unique; `[]` when no check ran
    (a direct apply), as #597 defines it.
  - **admin_mode**: whether the decider acted as a platform admin, from their scope.

  `decisions/2` lists an organization's rows newest first for the audits (#239), with a `before`
  cursor (domain: step 3's paging).
  """

  @behaviour Cadence.Governance.DecisionRecord

  import Ecto.Query

  alias Cadence.Configuration.{ChangeSetStore, Document, ReviewRow}
  alias Cadence.Governance.DecisionRecord
  alias Cadence.Repo

  # The term's version (#108: a golden test pins it). domain: D3's selections join the term; whoever
  # lands second bumps this to 2 with a new golden.
  @digest_version 1
  @limit 200

  @doc """
  sha256 (hex, `Configuration.Document.sha256/1`, the ledger's own content hash) of `[1,
  [[change_id, position, kind, entity_id, action, payload, base], …]]` over the staged ops in apply
  order (`ChangeSetStore.staged_ops/1`).
  """
  @spec digest([map()]) :: binary()
  def digest(staged_ops) do
    entries =
      for %{op: op} <- staged_ops,
          do: [
            op.change_id,
            op.position,
            op.kind,
            op.entity_id,
            op.action,
            op.payload || %{},
            op.base || %{}
          ]

    Document.sha256([@digest_version, entries])
  end

  @doc "The ids the separation check compared (`[submitter | authors]` as actors), sorted, unique."
  @spec separated_from([{:user | :service, binary()} | map() | nil]) :: [binary()]
  def separated_from(actors) do
    actors
    |> Enum.flat_map(&actor_id/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp actor_id({kind, id}) when kind in [:user, :service] and is_binary(id), do: [id]
  defp actor_id(%{"id" => id}) when is_binary(id), do: [id]
  defp actor_id(_other), do: []

  @doc """
  What the separation check compares (DECISIONS #14): the submitter and every change's author, as
  actors. The review records exactly this as `separated_from` (#599).
  """
  @spec compared(map()) :: [map() | {:user | :service, binary()} | nil]
  def compared(set) do
    authors =
      set.change_set_id
      |> ChangeSetStore.changes()
      |> Enum.map(&author_actor(&1.author_key))

    [set.submitted_by | authors]
  end

  defp author_actor("user:" <> id), do: {:user, id}
  defp author_actor("service:" <> id), do: {:service, id}
  defp author_actor(_other), do: nil

  @doc """
  In the apply's transaction (domain): a reviewed apply runs exactly the ops its review named
  (`{:error, :change_set_changed}` otherwise, so nothing is written); a direct apply writes its own
  `not_required` record.
  """
  @spec decided(map(), map(), [map()], map(), binary()) :: :ok | {:error, :change_set_changed}
  def decided(_set, _applier, ops, %{digest: digest}, _review_id) when is_binary(digest) do
    if digest(ops) == digest, do: :ok, else: {:error, :change_set_changed}
  end

  def decided(set, applier, ops, %{digest: nil, admin_mode: admin_mode}, review_id) do
    write(set, applier, "not_required", nil, review_id, %{
      digest: digest(ops),
      separated_from: [],
      admin_mode: admin_mode
    })

    :ok
  end

  @doc """
  Writes one decision row. `record` carries `:digest`, `:separated_from` and `:admin_mode`; the
  version and policy come from the set.
  """
  @spec write(map(), map(), binary(), binary() | nil, binary(), map()) :: ReviewRow.t()
  def write(set, actor, decision, comment, review_id, record) do
    Repo.insert!(%ReviewRow{
      review_id: review_id,
      change_set_id: set.change_set_id,
      organization_id: set.organization_id,
      mission_id: set.mission_id,
      decision: decision,
      actor: actor,
      comment: comment,
      decided_at: DateTime.utc_now(),
      subject_version: set.version,
      subject_digest: Map.fetch!(record, :digest),
      policy_document: policy!(set),
      separated_from: Map.fetch!(record, :separated_from),
      admin_mode: boolean!(Map.fetch!(record, :admin_mode))
    })
  end

  # domain on #616: no silent defaults. Every decision runs under a stored policy and a known mode.
  defp policy!(%{policy_document: %{} = policy}), do: policy

  defp policy!(set),
    do: raise(ArgumentError, "change set #{set.change_set_id} has no policy_document to record")

  defp boolean!(value) when is_boolean(value), do: value

  defp boolean!(value),
    do: raise(ArgumentError, "admin_mode must be a boolean, got #{inspect(value)}")

  @impl true
  def decisions(organization_id, opts \\ []) do
    ReviewRow
    |> where([row], row.organization_id == ^organization_id)
    |> before(Keyword.get(opts, :before))
    |> order_by([row], desc: row.decided_at, desc: row.review_id)
    |> limit(^min(Keyword.get(opts, :limit, @limit), @limit))
    |> Repo.all()
    |> Enum.map(&record/1)
  end

  # `before: {decided_at, review_id}` (the last row of the previous page), or a bare time.
  defp before(query, nil), do: query

  defp before(query, {%DateTime{} = at, id}) when is_binary(id),
    do:
      where(
        query,
        [row],
        row.decided_at < ^at or (row.decided_at == ^at and row.review_id < ^id)
      )

  defp before(query, %DateTime{} = at), do: where(query, [row], row.decided_at < ^at)

  # The table's check allows exactly these (migration 20261121090000).
  defp decision("approved"), do: :approved
  defp decision("sent_back"), do: :sent_back
  defp decision("not_required"), do: :not_required

  defp record(%ReviewRow{} = row) do
    %DecisionRecord{
      actor: row.actor,
      decision: decision(row.decision),
      reason: row.comment,
      decided_at: row.decided_at,
      subject: %{
        kind: "change_set",
        id: row.change_set_id,
        version: row.subject_version,
        digest: row.subject_digest,
        previous_digest: nil
      },
      policy: row.policy_document,
      admin_mode: row.admin_mode,
      separated_from: row.separated_from
    }
  end
end
