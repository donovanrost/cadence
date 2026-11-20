defmodule Cadence.Reads.MissionModelApprovals.CompositionKeys do
  @moduledoc """
  D2 (#543; design `mission-composition-design.md` §4, §6): the model approval read's keys for the
  composition a revision belongs to, beside its catalog revision (readers first):

  - `composition`: the shared object (`Reads.CompositionActors`), or nil for a revision no
    composition names.
  - `importers`: `[{layer_id, importers: [actor], importers_count}]`, per imported layer, the people
    and services E1's separation counts for it (the composer is `composition.created_by`, not
    repeated): at most 100 named, the count exact.
  - `breaking_base`: `ModelApprovalGate.default_baseline/3` itself (domain): exactly the revision
    approval compares against, `{revision_id, composition: {composition_id, number}, catalog_revision:
    {id, number}}`, each part nil when it has none.
  - `composer/4`: whether a separation refusal is the composer's alone (`cannot_decide_because:
    "composer"`): the viewer passes against the layers' importers but not with the composer added.
    A viewer who is also an importer stays `self_approval` (E1's precedence).
  """

  alias Cadence.Catalog
  alias Cadence.Catalog.ModelRevisions
  alias Cadence.Control.ModelApprovalGate
  alias Cadence.Governance.Accountability
  alias Cadence.MissionModels.{CompositionApproval, CompositionViews}
  alias Cadence.Reads.CompositionActors

  @importers_shown 100

  @doc "`%{revision_id => composition}` for a list of revisions (one lookup)."
  @spec for_list(binary(), binary(), [binary()]) :: %{binary() => map()}
  def for_list(organization_id, mission_id, revision_ids),
    do: CompositionActors.for_revisions(organization_id, mission_id, revision_ids)

  @doc "The read's `composition`, `importers` and `breaking_base` for one revision."
  @spec read(binary(), binary(), binary()) :: map()
  def read(organization_id, mission_id, revision_id) do
    case CompositionViews.for_revisions(organization_id, mission_id, [revision_id]) do
      %{^revision_id => view} ->
        layers = CompositionApproval.layer_importers(organization_id, mission_id, view)
        documents = [view.created_by | Enum.flat_map(layers, &elem(&1, 1))]
        names = CompositionActors.names(organization_id, documents)

        %{
          composition: CompositionActors.named(view, names),
          importers: importers(layers, names),
          breaking_base: breaking_base(organization_id, mission_id, revision_id)
        }

      _none ->
        %{
          composition: nil,
          importers: [],
          breaking_base: breaking_base(organization_id, mission_id, revision_id)
        }
    end
  end

  @doc """
  True when `person_id` is refused only because of the composer: they're separate from every
  layer's importers. The caller has already seen the full set refuse them (`self`).
  """
  @spec composer?(binary(), binary(), binary(), binary() | nil) :: boolean()
  def composer?(_organization_id, _mission_id, _revision_id, nil), do: false

  def composer?(organization_id, mission_id, revision_id, person_id) do
    case CompositionViews.for_revisions(organization_id, mission_id, [revision_id]) do
      %{^revision_id => view} ->
        layer_actors =
          organization_id
          |> CompositionApproval.layer_importers(mission_id, view)
          |> Enum.flat_map(&elem(&1, 1))
          |> Enum.map(&Catalog.model_import_actor_of/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        Catalog.model_import_actor_of(view.created_by) != nil and
          Accountability.separate(organization_id, {:user, person_id}, layer_actors) == :ok

      _none ->
        false
    end
  end

  # fe-setup on #609: the console reads at most 100 per layer, so the server sends at most 100
  # (the first recorded) and the exact count beside them.
  defp importers(layers, names) do
    for {layer_id, documents} <- layers do
      actors =
        documents |> Enum.map(&CompositionActors.actor(&1, names)) |> Enum.reject(&is_nil/1)

      %{
        layer_id: layer_id,
        importers: Enum.take(actors, @importers_shown),
        importers_count: length(actors)
      }
    end
  end

  defp breaking_base(organization_id, mission_id, revision_id) do
    case ModelApprovalGate.default_baseline(organization_id, mission_id, revision_id) do
      nil ->
        nil

      base_id ->
        composition =
          organization_id
          |> CompositionViews.for_revisions(mission_id, [base_id])
          |> Map.get(base_id)

        catalog =
          organization_id |> ModelRevisions.for_models(mission_id, [base_id]) |> Map.get(base_id)

        %{
          revision_id: base_id,
          composition: composition && Map.take(composition, [:composition_id, :number]),
          catalog_revision: catalog && Map.take(catalog, [:id, :number])
        }
    end
  end
end
