defmodule Cadence.Control.WithdrawnPins do
  @moduledoc """
  Which spacecraft are on a revision whose approval was withdrawn (E2, #546; design §5): the read
  behind the craft's state line, the attention item and commanding's `model_approval_withdrawn`
  HOLD (commanding's contract on #546).

  - Keyed on what the craft's **active generation runs** (its fleet entry's model revision), not
    on the profile's pin: that's the model a command is encoded and verified against, and the
    craft stays on it until a new configuration is applied (U109).
  - A fixed number of queries for any number of craft, never one per craft: the active
    activation, the craft's fleet entries, the withdrawn revisions among them, their decision
    records and their compositions.
  - `hold_basis` is `"<revision_id>:withdrawn:<decided_at>"`, so an acknowledgement covers exactly
    that decision. It gains the record id additively later (#878).
  """

  import Ecto.Query

  alias Cadence.Activations
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Catalog.ModelRevisions
  alias Cadence.Control.ActorRef

  alias Cadence.MissionModels.{
    CompositionViews,
    DecisionRow,
    RevisionDecisions,
    RevisionRow,
    Selection
  }

  alias Cadence.Repo

  @type pin :: %{
          composition_id: binary() | nil,
          revision_id: binary(),
          decision: map(),
          hold_basis: binary(),
          earlier_approved: %{revision_id: binary(), catalog_revision: map() | nil} | nil
        }

  @doc "`%{spacecraft_id => pin()}` for the affected craft among `spacecraft_ids` only."
  @spec for_spacecraft(binary(), binary(), [binary()], map() | nil) :: %{binary() => pin()}
  def for_spacecraft(organization_id, mission_id, spacecraft_ids, activation \\ nil)

  def for_spacecraft(_organization_id, _mission_id, [], _activation), do: %{}

  def for_spacecraft(organization_id, mission_id, spacecraft_ids, activation)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(spacecraft_ids) do
    running = running(organization_id, mission_id, Enum.uniq(spacecraft_ids), activation)
    withdrawn = withdrawn(organization_id, mission_id, running |> Map.values() |> Enum.uniq())

    if withdrawn == %{} do
      %{}
    else
      compositions =
        CompositionViews.ids_for_revisions(organization_id, mission_id, Map.keys(withdrawn))

      names = ActorRef.names(organization_id, withdrawn |> Map.values() |> Enum.map(& &1.actor))

      pins =
        for {spacecraft_id, revision_id} <- running,
            %DecisionRow{} = record <- [Map.get(withdrawn, revision_id)],
            into: %{},
            do:
              {spacecraft_id, pin(revision_id, record, Map.get(compositions, revision_id), names)}

      with_earlier(organization_id, mission_id, pins)
    end
  end

  @doc """
  The basis of commanding's `model_approval_withdrawn` HOLD over `pins` (this module's
  `for_spacecraft/3` answer for the held craft): a hash of each craft with its own decision's
  `hold_basis`. The preflight shows it, and a GO or a submit that carries an acknowledgement
  recomputes it under its lock, so an acknowledgement covers exactly those craft on exactly those
  decisions (E2c, #546).
  """
  @spec basis(%{binary() => pin()}) :: binary()
  def basis(pins) do
    pins
    |> Enum.map(fn {spacecraft_id, pin} -> {spacecraft_id, pin.hold_basis} end)
    |> Enum.sort()
    |> then(&{:model_approval_withdrawn, &1})
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 32)
  end

  @doc "Every withdrawn revision any craft of the mission runs, with its craft: `%{revision_id => [spacecraft_id]}`."
  @spec affected(binary(), binary()) :: %{binary() => [binary()]}
  def affected(organization_id, mission_id) do
    with {:ok, activation} <- Activations.fetch_active_activation(organization_id, mission_id),
         {:ok, entries} <- FleetSnapshot.entries(activation.metadata) do
      running = Map.new(entries, fn {id, entry} -> {id, revision(entry)} end)
      withdrawn = withdrawn(organization_id, mission_id, running |> Map.values() |> Enum.uniq())

      running
      |> Enum.filter(fn {_id, revision} -> Map.has_key?(withdrawn, revision) end)
      |> Enum.group_by(fn {_id, revision} -> revision end, fn {id, _revision} -> id end)
    else
      _none -> %{}
    end
  end

  # `activation`: the one the caller already holds (under the command-basis lock), else the active one.
  defp running(organization_id, mission_id, spacecraft_ids, held) do
    with {:ok, activation} <- held_or_active(held, organization_id, mission_id),
         {:ok, entries} <- FleetSnapshot.entries_for(activation.metadata, spacecraft_ids) do
      for {id, entry} <- entries,
          revision = revision(entry),
          is_binary(revision),
          into: %{},
          do: {id, revision}
    else
      _none -> %{}
    end
  end

  defp held_or_active(nil, organization_id, mission_id),
    do: Activations.fetch_active_activation(organization_id, mission_id)

  defp held_or_active(activation, _organization_id, _mission_id), do: {:ok, activation}

  # A fleet entry's model revision (fleet snapshot v2; #764 deleted the v1 path).
  defp revision(%{"mission_model" => %{"revision_id" => id}}) when is_binary(id), do: id
  defp revision(_entry), do: nil

  # `%{revision_id => withdrawal record}` for the withdrawn revisions among `revision_ids`.
  defp withdrawn(_organization_id, _mission_id, []), do: %{}

  defp withdrawn(organization_id, mission_id, revision_ids) do
    from(decision in DecisionRow,
      join: revision in RevisionRow,
      on: revision.revision_id == decision.revision_id,
      where:
        decision.organization_id == ^organization_id and decision.mission_id == ^mission_id and
          decision.revision_id in ^revision_ids and decision.decision == "withdrawn" and
          revision.status == "withdrawn",
      select: decision
    )
    |> Repo.all()
    |> Map.new(&{&1.revision_id, &1})
  end

  # U109's way out: per composition, the revision the next staging would select (an earlier
  # approved, runnable version) with its catalog revision, or nil when nothing approved is left.
  # One selection per distinct composition, and one catalog read.
  defp with_earlier(organization_id, mission_id, pins) do
    earlier =
      for composition <- pins |> Map.values() |> Enum.map(& &1.composition_id) |> Enum.uniq(),
          is_binary(composition),
          {:ok, revision} <- [Selection.select(organization_id, mission_id, composition)],
          into: %{},
          do: {composition, revision}

    catalogs = ModelRevisions.for_models(organization_id, mission_id, Map.values(earlier))

    Map.new(pins, fn {id, pin} ->
      revision = Map.get(earlier, pin.composition_id)

      {id,
       Map.put(
         pin,
         :earlier_approved,
         revision && %{revision_id: revision, catalog_revision: Map.get(catalogs, revision)}
       )}
    end)
  end

  defp pin(revision_id, record, composition_id, names) do
    %{
      composition_id: composition_id,
      revision_id: revision_id,
      decision: decision(record, names),
      hold_basis: "#{revision_id}:withdrawn:#{DateTime.to_iso8601(record.decided_at)}"
    }
  end

  @doc """
  A withdrawal record as the reads show it: `{revision_id, kind, by, at, reason}`. `by` is
  `{kind, id, name}` by #146's rule C1 (`Control.ActorRef`: a member by their current name, never
  a stored name or an email), with `names` from `ActorRef.names/2` over the records' actors.
  """
  @spec decision(DecisionRow.t(), ActorRef.names()) :: map()
  def decision(%DecisionRow{} = record, names) do
    %{
      revision_id: record.revision_id,
      kind: "withdrawn",
      by: ActorRef.document(record.actor, names),
      at: record.decided_at,
      reason: record.reason
    }
  end

  @doc """
  The withdrawal behind a composition's `:withdrawn` selection (its newest withdrawn link's
  record), for `details.decision` on the staging NO-GO and `restage_needed` (U109); nil when none.
  """
  @spec composition_decision(binary(), binary(), binary()) :: map() | nil
  def composition_decision(organization_id, mission_id, composition_id) do
    with %{revision_id: revision_id} <-
           organization_id
           |> Selection.ranked(mission_id, composition_id)
           |> Enum.find(&(&1.status == "withdrawn")),
         %DecisionRow{} = record <-
           RevisionDecisions.withdrawal(organization_id, mission_id, revision_id) do
      decision(record, ActorRef.names(organization_id, [record.actor]))
    else
      _none -> nil
    end
  end
end
