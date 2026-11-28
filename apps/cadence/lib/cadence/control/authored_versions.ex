defmodule Cadence.Control.AuthoredVersions do
  @moduledoc """
  Records a version of the mission's authored monitoring layer as approved by the monitoring
  change set being applied (ADR-020 P3, #451): the only way a version, and so an authored head,
  comes to exist.

  The apply builds its generation before it writes the ledger revision and marks the set applied,
  and the generation needs the head, so the version is recorded **during** the apply (M2; agreed
  with commanding and mm-engineer on #451). It is held to the facts twice:

    * **now**, under a lock on the set, with a named refusal for a wrong call
      (`:authored_version_change_set_mismatch`):
      - the set is this organization's and mission's, in the monitoring lane, and not yet applied;
      - its approval is settled: an `open` set whose policy applies it directly, or an
        `in_review` set whose latest review approved its current version;
      - `revision_number` is the locked mission head's number plus one, the revision this apply
        writes;
      - the layer is an authored layer of this mission, and the set records no other version
        (`MissionModels.AuthoredHead.insert_version/4`);
    * **at commit**, by the database: a deferred constraint trigger refuses the version unless its
      set is then `applied` as exactly `revision_number`, and a deferred foreign key unless that
      ledger revision exists. A transaction that doesn't complete the apply can't commit the
      version, and no other transaction reads the head before commit.

  `refusal/1` maps a commit-time constraint failure to the same closed errors. Run inside the
  apply's transaction, under the mission head lock.
  """

  alias Cadence.Configuration.{ChangeSetRow, ChangeSetStore, Ledger, ReviewRow}
  alias Cadence.MissionModels.AuthoredHead

  @commit_constraints %{
    "mission_model_authored_versions_applied" => :authored_version_not_applied,
    "mission_model_authored_versions_revision_fk" => :authored_version_revision_unknown
  }

  @doc """
  Records `layer_id` for `applying`, the set as the apply holds it: its row is locked and checked
  in the database, and its policy (`policy_document`) is the one the apply validated, which a
  direct apply carries in memory before the set is written.
  """
  @spec record(binary(), binary(), binary(), ChangeSetRow.t(), pos_integer()) ::
          {:ok, AuthoredHead.version()} | {:error, term()}
  def record(organization_id, mission_id, layer_id, %ChangeSetRow{} = applying, revision_number)
      when is_binary(layer_id) and is_integer(revision_number) do
    with {:ok, set, approval} <-
           applying_set(organization_id, mission_id, applying, revision_number) do
      AuthoredHead.insert_version(organization_id, mission_id, layer_id, %{
        change_set_id: set.change_set_id,
        revision_number: revision_number,
        approval: approval
      })
    end
  end

  @doc """
  The closed error for a commit-time refusal of a version (a `Postgrex.Error` raised by
  `Repo.transaction` when the deferred checks fail), or nil for any other error.
  """
  @spec refusal(term()) :: atom() | nil
  def refusal(%Postgrex.Error{postgres: %{constraint: constraint}}),
    do: Map.get(@commit_constraints, constraint)

  def refusal(_error), do: nil

  defp applying_set(organization_id, mission_id, applying, revision_number) do
    head = Ledger.lock_head(organization_id, mission_id)

    with {:ok, %ChangeSetRow{organization_id: ^organization_id, lane: "monitoring"} = set} <-
           ChangeSetStore.lock_set(mission_id, applying.change_set_id),
         true <- is_nil(set.applied_revision_number),
         true <- revision_number == head.revision_number + 1,
         {:ok, approval} <- approval(%{set | policy_document: applying.policy_document}) do
      {:ok, set, approval}
    else
      _other -> {:error, :authored_version_change_set_mismatch}
    end
  end

  # Settled before the apply: a direct set by its own policy, or a reviewed set whose latest
  # review approved the version being applied.
  defp approval(%ChangeSetRow{state: "open", policy_document: %{"approval_required" => false}}),
    do: {:ok, "direct"}

  defp approval(%ChangeSetRow{state: "in_review"} = set) do
    case set.change_set_id |> ChangeSetStore.reviews() |> List.last() do
      %ReviewRow{decision: "approved", subject_version: version} when version == set.version ->
        {:ok, "reviewed"}

      _none ->
        :error
    end
  end

  defp approval(_set), do: :error
end
