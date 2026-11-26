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
          hold_basis: binary()
        }

  @doc "`%{spacecraft_id => pin()}` for the affected craft among `spacecraft_ids` only."
  @spec for_spacecraft(binary(), binary(), [binary()]) :: %{binary() => pin()}
  def for_spacecraft(_organization_id, _mission_id, []), do: %{}

  def for_spacecraft(organization_id, mission_id, spacecraft_ids)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(spacecraft_ids) do
    running = running(organization_id, mission_id, Enum.uniq(spacecraft_ids))
    withdrawn = withdrawn(organization_id, mission_id, running |> Map.values() |> Enum.uniq())

    if withdrawn == %{} do
      %{}
    else
      compositions =
        CompositionViews.ids_for_revisions(organization_id, mission_id, Map.keys(withdrawn))

      names = ActorRef.names(organization_id, withdrawn |> Map.values() |> Enum.map(& &1.actor))

      for {spacecraft_id, revision_id} <- running,
          %DecisionRow{} = record <- [Map.get(withdrawn, revision_id)],
          into: %{},
          do: {spacecraft_id, pin(revision_id, record, Map.get(compositions, revision_id), names)}
    end
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

  defp running(organization_id, mission_id, spacecraft_ids) do
    with {:ok, activation} <- Activations.fetch_active_activation(organization_id, mission_id),
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
