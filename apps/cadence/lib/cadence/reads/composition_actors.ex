defmodule Cadence.Reads.CompositionActors do
  @moduledoc """
  D2 (#543): the compositions the reads show, with their actors named (#146 via `Control.ActorRef`,
  #472), and the actor shape shared by `composition.created_by` and the approval read's per-layer
  importers: `%{kind, id, name, run_by}`.

  - A person: `id` and `name` only while an active member of the mission's organization, checked
    at read time (a member without a display name keeps the id, `name: nil`); anyone else reads
    `id: nil, name: nil`.
  - A service of the organization: its id and live name; another organization's reads nils.
  - A system actor (a seed, a script): its stored system id, `name` nil (the console says
    "Cadence"), and `run_by: %{id, name}` naming who ran it by the same member rule (#513, as
    `Reads.Catalog.Requesters` does, #516). `run_by` is nil for everyone else.
  - The composition migration's own actor reads `nil` (mms-engineer): it made nobody's choice.

  Never an email: D1 stores kind and ids only. One name lookup per read.
  """

  alias Cadence.Control.ActorRef
  alias Cadence.MissionModels.CompositionViews
  alias Cadence.Persistence.JsonDocument

  @migration_actor "migration:20261120060000"

  @type actor :: %{
          kind: binary(),
          id: binary() | nil,
          name: binary() | nil,
          run_by: %{id: binary() | nil, name: binary() | nil} | nil
        }

  @doc "`%{revision_id => composition}` with `created_by` named, for the revisions that have one."
  @spec for_revisions(binary(), binary(), [binary() | nil]) :: %{binary() => map()}
  def for_revisions(organization_id, mission_id, revision_ids) do
    views = CompositionViews.for_revisions(organization_id, mission_id, revision_ids)
    names = names(organization_id, views |> Map.values() |> Enum.map(& &1.created_by))
    Map.new(views, fn {revision_id, view} -> {revision_id, named(view, names)} end)
  end

  @doc "A composition view with `created_by` named, given `names/2` over its documents."
  @spec named(CompositionViews.t(), ActorRef.names()) :: map()
  def named(view, names), do: Map.update!(view, :created_by, &actor(&1, names))

  @doc "What `actor/2` needs for `documents` (stored actor documents, wrapped or not)."
  @spec names(binary() | nil, [term()]) :: ActorRef.names()
  def names(organization_id, documents) do
    documents = Enum.map(documents, &unwrap/1)
    runners = for %{"run_by" => id} <- documents, is_binary(id) and id != "", do: id
    ActorRef.names(organization_id, documents ++ runners)
  end

  @doc "One stored actor document as the reads show it (`nil` for the migration's own actor)."
  @spec actor(term(), ActorRef.names()) :: actor() | nil
  def actor(document, names) do
    case unwrap(document) do
      %{"actor_kind" => "system", "system_id" => @migration_actor} = doc
      when not is_map_key(doc, "run_by") ->
        nil

      %{} = doc ->
        with %{} = actor <- ActorRef.document(doc, names),
             do: Map.put(actor, :run_by, runner(doc, names))

      _other ->
        nil
    end
  end

  defp runner(%{"actor_kind" => "system", "run_by" => id}, names)
       when is_binary(id) and id != "" do
    case ActorRef.ref(id, names) do
      %{kind: "user"} = person -> Map.take(person, [:id, :name])
      _not_a_person -> %{id: nil, name: nil}
    end
  end

  defp runner(_document, _names), do: nil

  defp unwrap(document), do: JsonDocument.unwrap_value(document)
end
