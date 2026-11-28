defmodule Cadence.MissionModels.EffectiveStatuses do
  @moduledoc """
  The approval status a revision has for running it (ADR-020 P3 slice M1, #451; the addendum's
  #92 a).

  A revision linked at an authored head, `(composition, head)`, is never approved on its own: it
  is its composition's **base** (the same composition's head-nil link at the same compiler version)
  plus a recorded version of the mission's authored layer, which its applied change set approved.
  So, derived at read time and never stored:

    * approved, when the base is approved and the head is a recorded version;
    * withdrawn, when the base's approval was withdrawn (so withdrawing the base withdraws every
      head built on it);
    * otherwise the base's own status (candidate, rejected, ...), or `:candidate` when no base is
      linked at that compiler version.

  Any other revision has its stored status. A fixed number of queries for any number of revisions.
  """

  import Ecto.Query

  alias Cadence.MissionModels
  alias Cadence.MissionModels.{AuthoredHead, EffectiveRevisionRow}
  alias Cadence.Repo

  @doc """
  The revision whose approval each of `revision_ids` carries: a revision at an authored head maps
  to its base, any other to itself, and a head revision with no base at its compiler version to
  nil. The withdrawal read uses it, so a withdrawn base reaches every craft running a head on it.
  """
  @spec approval_bases(binary(), binary(), [binary()]) :: %{binary() => binary() | nil}
  def approval_bases(_organization_id, _mission_id, []), do: %{}

  def approval_bases(organization_id, mission_id, revision_ids) do
    heads = head_links(organization_id, mission_id, revision_ids)
    bases = if heads == [], do: %{}, else: bases(organization_id, mission_id, heads)

    by_head =
      Map.new(heads, &{&1.revision_id, Map.get(bases, {&1.composition_id, &1.compiler_version})})

    Map.new(revision_ids, &{&1, Map.get(by_head, &1, &1)})
  end

  @doc "The authored head each of `revision_ids` is linked at (nil for a base, or no link)."
  @spec authored_heads(binary(), binary(), [binary()]) :: %{binary() => binary() | nil}
  def authored_heads(_organization_id, _mission_id, []), do: %{}

  def authored_heads(organization_id, mission_id, revision_ids) do
    linked =
      organization_id
      |> head_links(mission_id, revision_ids)
      |> Map.new(&{&1.revision_id, &1.head})

    Map.new(revision_ids, &{&1, Map.get(linked, &1)})
  end

  @spec statuses(binary(), binary(), [binary()]) :: %{binary() => atom()}
  def statuses(_organization_id, _mission_id, []), do: %{}

  def statuses(organization_id, mission_id, revision_ids) do
    stored = MissionModels.revision_statuses(organization_id, mission_id, revision_ids)

    case head_links(organization_id, mission_id, revision_ids) do
      [] -> stored
      heads -> Map.merge(stored, derived(organization_id, mission_id, heads))
    end
  end

  defp derived(organization_id, mission_id, heads) do
    bases = bases(organization_id, mission_id, heads)

    base_statuses =
      MissionModels.revision_statuses(organization_id, mission_id, Map.values(bases))

    recorded =
      AuthoredHead.recorded(
        organization_id,
        mission_id,
        heads |> Enum.map(& &1.head) |> Enum.uniq()
      )

    Map.new(heads, fn head ->
      base = Map.get(bases, {head.composition_id, head.compiler_version})

      {head.revision_id,
       status(Map.get(base_statuses, base), MapSet.member?(recorded, head.head))}
    end)
  end

  defp status(:approved, true), do: :approved
  defp status(:approved, false), do: :candidate
  defp status(nil, _recorded), do: :candidate
  defp status(base, _recorded), do: base

  defp head_links(organization_id, mission_id, revision_ids) do
    from(link in EffectiveRevisionRow,
      where:
        link.organization_id == ^organization_id and link.mission_id == ^mission_id and
          link.revision_id in ^revision_ids and not is_nil(link.authored_head),
      select: %{
        revision_id: link.revision_id,
        composition_id: link.composition_id,
        head: link.authored_head,
        compiler_version: link.compiler_version
      }
    )
    |> Repo.all()
  end

  # `%{{composition_id, compiler_version} => base revision_id}`.
  defp bases(organization_id, mission_id, heads) do
    compositions = heads |> Enum.map(& &1.composition_id) |> Enum.uniq()

    from(link in EffectiveRevisionRow,
      where:
        link.organization_id == ^organization_id and link.mission_id == ^mission_id and
          link.composition_id in ^compositions and is_nil(link.authored_head),
      select: {{link.composition_id, link.compiler_version}, link.revision_id}
    )
    |> Repo.all()
    |> Map.new()
  end
end
