defmodule Cadence.Reads.WithdrawnApprovalAttention do
  @moduledoc """
  The `model_approval_withdrawn` source of the mission attention read (E2, #546; U109): a craft
  whose active generation runs a revision whose approval was withdrawn. One item per craft, id
  `<revision_id>:<spacecraft_id>`, high severity, its facts nested in `withdrawal` (console's
  `now/withdrawnComposition.ts`):
  `{revision_id, catalog_revision, kind, decided_by, decided_at, reason, composition,
  earlier_approved}`.

  It comes from the same read as the craft's state line and commanding's HOLD
  (`Control.WithdrawnPins`), so they always agree. Derived on every read: there's nothing to
  acknowledge, and the item leaves when the craft runs an approved revision. `earlier_approved`
  is what the next staging would select (the way out), or nil when nothing approved is left.
  """

  alias Cadence.Catalog.ModelRevisions
  alias Cadence.Control.WithdrawnPins
  alias Cadence.MissionModels.Selection
  alias Cadence.Reads.MissionModelApprovals.CompositionKeys

  @source "model_approval_withdrawn"

  def source, do: @source

  @doc "Open items, one per affected craft."
  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    affected = WithdrawnPins.affected(org, mission)
    craft = affected |> Map.values() |> List.flatten()

    if craft == [] do
      []
    else
      pins = WithdrawnPins.for_spacecraft(org, mission, craft)
      revisions = Map.keys(affected)
      compositions = CompositionKeys.for_list(org, mission, revisions)
      earlier = earlier(org, mission, pins)
      catalogs = ModelRevisions.for_models(org, mission, revisions ++ Map.values(earlier))

      for {spacecraft_id, pin} <- Enum.sort(pins) do
        item(spacecraft_id, pin, compositions, catalogs, Map.get(earlier, pin.composition_id))
      end
    end
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(_org, _mission, _since), do: []

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission), do: %{open: length(items(org, mission)), acknowledged: 0}

  # The revision each affected composition would select next, if any (`Selection.select/3`).
  defp earlier(org, mission, pins) do
    for composition <- pins |> Map.values() |> Enum.map(& &1.composition_id) |> Enum.uniq(),
        is_binary(composition),
        {:ok, revision} <- [Selection.select(org, mission, composition)],
        into: %{},
        do: {composition, revision}
  end

  defp item(spacecraft_id, pin, compositions, catalogs, earlier) do
    decision = pin.decision

    %{
      id: "#{pin.revision_id}:#{spacecraft_id}",
      source: @source,
      state: "open",
      severity: "crit",
      spacecraft_id: spacecraft_id,
      raised_at: decision.at,
      since: decision.at,
      acknowledged_by: nil,
      resolution: nil,
      withdrawal: %{
        revision_id: pin.revision_id,
        catalog_revision: Map.get(catalogs, pin.revision_id),
        kind: decision.kind,
        decided_by: decision.by,
        decided_at: decision.at,
        reason: decision.reason,
        composition: Map.get(compositions, pin.revision_id),
        earlier_approved:
          earlier && %{revision_id: earlier, catalog_revision: Map.get(catalogs, earlier)}
      }
    }
  end
end
