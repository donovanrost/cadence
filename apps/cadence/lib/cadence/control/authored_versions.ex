defmodule Cadence.Control.AuthoredVersions do
  @moduledoc """
  Records a version of the mission's authored monitoring layer as approved by an applied
  monitoring change set (ADR-020 P3 slice M1, #451): the only way a version, and so an authored
  head, comes to exist. It is the approval of the layer, so it holds every fact to the stores
  under a lock on the set (commanding's and mm-engineer's reviews of #1098) and refuses anything
  else:

    * the set is this organization's and mission's, in the monitoring lane, `applied`, as exactly
      `revision_number` (`:authored_version_change_set_mismatch`);
    * the layer is an authored layer of this mission, and the set records no other version
      (`MissionModels.AuthoredHead.insert_version/4`).

  The version says how the set was approved: `reviewed` (its own review) or `direct` (a 'direct'
  apply, #93 b). Lives in control because it reads the configuration store and the mission model
  together. Run inside the apply's transaction, after the set is marked applied, under the
  mission head lock.
  """

  alias Cadence.Configuration.{ChangeSetRow, ChangeSetStore}
  alias Cadence.MissionModels.AuthoredHead

  @spec record(binary(), binary(), binary(), binary(), pos_integer()) ::
          {:ok, AuthoredHead.version()} | {:error, term()}
  def record(organization_id, mission_id, layer_id, change_set_id, revision_number)
      when is_binary(layer_id) and is_binary(change_set_id) and is_integer(revision_number) do
    with {:ok, set} <- applied_set(organization_id, mission_id, change_set_id, revision_number) do
      AuthoredHead.insert_version(organization_id, mission_id, layer_id, %{
        change_set_id: set.change_set_id,
        revision_number: revision_number,
        approval: approval(set)
      })
    end
  end

  defp applied_set(organization_id, mission_id, change_set_id, revision_number) do
    case ChangeSetStore.lock_set(mission_id, change_set_id) do
      {:ok,
       %ChangeSetRow{
         organization_id: ^organization_id,
         lane: "monitoring",
         state: "applied",
         applied_revision_number: ^revision_number
       } = set} ->
        {:ok, set}

      _other ->
        {:error, :authored_version_change_set_mismatch}
    end
  end

  # The set's own review approved the layer, unless its policy let it apply directly.
  defp approval(%ChangeSetRow{policy_document: %{"approval_required" => false}}), do: "direct"
  defp approval(%ChangeSetRow{}), do: "reviewed"
end
