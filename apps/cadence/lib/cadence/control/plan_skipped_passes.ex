defmodule Cadence.Control.PlanSkippedPasses do
  @moduledoc """
  #273: the passes a plan approval leaves out because their booking window has closed, in the
  shape the console reads (`expired`):
  `%{count, reservable_count, items: [%{snapshot_id, spacecraft, station, aos, expires_at, reason}]}`
  or `nil` when there are none.

  It never decides WHICH passes those are. The set comes from the domain's one rule
  (`ContactPlanApprovals.expired_set/5`, before a decision) or from what a decision recorded
  (`approval.skipped`). This module only describes those ids from the plan version's immutable
  snapshots: spacecraft, station, AOS, the offer's expiry.

  Items are in AOS order, capped at 5,000; `count` is never capped. The keys are strings and the
  times ISO-8601, so a stored (replayed) answer reads the same as a fresh one.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.ContactPlanning.ContactPlanApprovals
  alias Cadence.ContactPlanning.ExpiredPasses
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.SpacecraftStore

  @max_items 5_000

  @doc """
  The plan read's fields (#273): `expired`, `expired_digest` (opaque, sent back unchanged on
  approve), `next_expiry_at` (when the set next changes, margin applied) and
  `expiry_margin_seconds`, from one call to the domain's rule at `now`.
  """
  @spec for_read(binary(), binary(), binary(), pos_integer(), DateTime.t()) :: map()
  def for_read(organization_id, mission_id, plan_id, version, %DateTime{} = now) do
    case ContactPlanApprovals.expired_set(organization_id, mission_id, plan_id, version, now) do
      {:ok, set} ->
        %{
          expired: describe(organization_id, mission_id, plan_id, version, set.skipped),
          expired_digest: set.digest,
          next_expiry_at: set.next_expiry_at,
          expiry_margin_seconds: ExpiredPasses.margin_seconds()
        }

      # Only when the plan or version is gone (the read 404s first). The contract keeps
      # expired_digest always present: the empty set's, and the approve recomputes and fails
      # closed anyway (domain's review).
      {:error, _missing} ->
        %{
          expired: nil,
          expired_digest: ExpiredPasses.digest([]),
          next_expiry_at: nil,
          expiry_margin_seconds: ExpiredPasses.margin_seconds()
        }
    end
  end

  @doc "A set's (or a decision's) skipped passes in the console's `expired` shape; `nil` for none."
  @spec describe(binary(), binary(), binary(), pos_integer(), [map()] | nil) :: map() | nil
  def describe(_organization_id, _mission_id, _plan_id, _version, skipped)
      when skipped in [nil, []],
      do: nil

  def describe(organization_id, mission_id, plan_id, version, skipped) when is_list(skipped) do
    selected =
      ManagementContacts.selected_opportunities(organization_id, mission_id, plan_id, version)

    by_id = Map.new(selected, &{&1.contact_opportunity_snapshot_id, &1})

    shown =
      skipped
      |> Enum.map(&{&1, Map.get(by_id, &1["snapshot_id"])})
      |> Enum.reject(fn {_entry, snapshot} -> is_nil(snapshot) end)
      |> Enum.sort_by(fn {_entry, snapshot} ->
        DateTime.to_unix(snapshot.starts_at, :microsecond)
      end)
      |> Enum.take(@max_items)

    stations = StationRefs.index(organization_id, mission_id)
    craft = spacecraft(organization_id, mission_id, Enum.map(shown, &elem(&1, 1)))

    %{
      "count" => length(skipped),
      "reservable_count" => max(length(selected) - length(skipped), 0),
      "items" =>
        Enum.map(shown, fn {entry, snapshot} -> item(entry, snapshot, craft, stations) end)
    }
  end

  defp item(entry, snapshot, craft, stations),
    do: %{
      "snapshot_id" => snapshot.contact_opportunity_snapshot_id,
      "spacecraft" => Map.get(craft, spacecraft_id(snapshot)),
      "station" => station(StationRefs.of_snapshot(snapshot, stations)),
      "aos" => DateTime.to_iso8601(snapshot.starts_at),
      "expires_at" => iso(snapshot.expires_at),
      "reason" => entry["reason"]
    }

  defp spacecraft(organization_id, mission_id, snapshots) do
    ids = snapshots |> Enum.map(&spacecraft_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    case SpacecraftStore.fetch_spacecrafts(organization_id, mission_id, ids) do
      {:ok, found} ->
        Map.new(found, fn {id, craft} ->
          {id, %{"id" => id, "name" => craft.display_name, "scid" => craft.scid}}
        end)

      # Past the store's batch bound: the items still count, with no names.
      {:error, _bounds} ->
        %{}
    end
  end

  defp spacecraft_id(snapshot), do: (snapshot.route_binding_document || %{})["spacecraft_id"]

  defp station(%{id: nil, code: nil, name: nil}), do: nil
  defp station(ref), do: %{"id" => ref.id, "code" => ref.code, "name" => ref.name}

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp iso(_none), do: nil
end
