defmodule Cadence.Spacecraft.ConfigKinds.Spacecraft do
  @moduledoc """
  Change-set kind for spacecraft identity, profile pin and its commanding and telemetry switches.

  Document: `%{"display_name", "scid", "spacecraft_type_id", "spacecraft_type_version",
  "metadata", "commanding_enabled", "telemetry_enabled"}`. The switches (L22) are what a change
  set set: `true`/`false`, or `nil` while the spacecraft's own configuration still decides (the
  configuration read shows that running value). Setting one is a runtime generation (the
  configuration follows, `Cadence.Control.ConfigurationSwitches`), with the HOLDs in
  `SwitchCompatibility`. Deleting a spacecraft archives it (#49/#50): it leaves the mission's lists, fleet
  and planning but keeps its id, SCID and history. Archiving raises the HOLDs in `ArchiveHolds`
  (waiting command requests block; booked passes and past traffic are acknowledged).

  Pin rules: a pin names an existing, active profile
  version; synthetic configuration profiles can't be chosen; a spacecraft whose framing is
  governed by its configuration review keeps its pin. Identity changes have no direct runtime
  effect: runtime pipelines pick spacecraft configuration up through activation.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Spacecraft, as: SpacecraftAsset
  alias Cadence.Spacecraft.ConfigKinds.{ArchiveHolds, ScidHolds, SpacecraftChecks}
  alias Cadence.Spacecraft.StagedScids
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Bulk

  @switches ~w(commanding_enabled telemetry_enabled)
  @fields ~w(display_name scid spacecraft_type_id spacecraft_type_version metadata) ++ @switches

  @impl true
  def kind, do: "spacecraft"

  @impl true
  def id_prefix, do: "spacecraft"

  @impl true
  def load(organization_id, mission_id, ids) do
    ids
    |> Enum.chunk_every(100)
    |> Enum.flat_map(fn chunk ->
      {:ok, found} = SpacecraftStore.fetch_spacecrafts(organization_id, mission_id, chunk)
      Map.values(found)
    end)
    |> Enum.reject(&SpacecraftAsset.archived?/1)
    |> Map.new(&{&1.spacecraft_id, document(&1)})
  end

  @impl true
  def normalize(:delete, _id, nil), do: {:ok, nil}

  def normalize(_action, _id, %{} = document) do
    document = Map.put_new(document, "metadata", %{})

    errors =
      F.only(document, @fields) ++
        F.text(document, "display_name", 1..200, required: true, label: "Name") ++
        F.integer(document, "scid", 0..1023, label: "SCID") ++
        F.text(document, "spacecraft_type_id", 1..120, label: "Profile") ++
        F.integer(document, "spacecraft_type_version", 1..1_000_000, label: "Profile version") ++
        F.map(document, "metadata") ++ pin_pair(document) ++ switch_errors(document)

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the spacecraft details")]}

  @impl true
  def validate(_organization_id, _mission_id, :delete, _entity_id, _previous, nil), do: :ok

  def validate(organization_id, mission_id, action, entity_id, previous, proposed) do
    change = %{action: action, id: entity_id, current: previous, proposed: proposed}
    context = SpacecraftChecks.context(organization_id, mission_id, [change])

    case SpacecraftChecks.check(context, change) do
      {[], _context} -> :ok
      {errors, _context} -> {:error, errors}
    end
  end

  # The whole consecutive run of spacecraft changes is checked and written together (#1049): the
  # reads once, one statement per kind of write, whatever the fleet's size.
  @impl true
  def batchable?(_op), do: true

  @impl true
  def load_batch(organization_id, mission_id, ids),
    do: {load(organization_id, mission_id, ids), nil}

  @impl true
  def write_batch(organization_id, mission_id, transitions, _context) do
    {checked, _context} =
      Enum.map_reduce(
        transitions,
        SpacecraftChecks.context(organization_id, mission_id, transitions),
        fn change, context ->
          case SpacecraftChecks.check(context, change) do
            {[], context} -> {{:ok, change}, context}
            {errors, context} -> {{:invalid, errors}, context}
          end
        end
      )

    passed = for {:ok, change} <- checked, do: Map.put(change, :actor, actor(change.op))

    with {:ok, documents} <- write_changes(organization_id, mission_id, passed) do
      {:ok,
       Enum.map(checked, fn
         {:ok, change} -> {:ok, Map.fetch!(documents, change.id)}
         {:invalid, errors} -> {:invalid, errors}
       end)}
    end
  end

  @impl true
  def write(organization_id, mission_id, action, id, previous, proposed, options) do
    change = %{
      action: action,
      id: id,
      current: previous,
      proposed: proposed,
      actor: actor_in(options)
    }

    with {:ok, documents} <- write_changes(organization_id, mission_id, [change]),
         do: {:ok, Map.fetch!(documents, id), []}
  end

  # Deletes archive first (they touch no SCID), then updates (SCIDs that move are cleared before
  # they are set), then creates, so no SCID is ever held twice on the way to the final state.
  defp write_changes(organization_id, mission_id, changes) do
    by_action = Enum.group_by(changes, & &1.action)
    deletes = Map.get(by_action, :delete, [])

    with :ok <- archive(organization_id, mission_id, deletes),
         {:ok, updated} <-
           Bulk.update(
             organization_id,
             mission_id,
             Enum.map(Map.get(by_action, :update, []), &update(organization_id, mission_id, &1))
           ),
         {:ok, created} <-
           Bulk.insert(
             organization_id,
             mission_id,
             Enum.map(Map.get(by_action, :create, []), &create(organization_id, mission_id, &1))
           ) do
      archived = Map.new(deletes, &{&1.id, nil})

      Enum.reduce(updated ++ created, archived, &Map.put(&2, &1.spacecraft_id, document(&1)))
      |> then(&{:ok, &1})
    end
  end

  defp archive(organization_id, mission_id, deletes) do
    deletes
    |> Enum.group_by(& &1.actor, & &1.id)
    |> Enum.reduce_while(:ok, fn {actor, ids}, :ok ->
      case Bulk.archive(organization_id, mission_id, ids, actor) do
        :ok -> {:cont, :ok}
        {:error, _id, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp create(organization_id, mission_id, %{id: id, proposed: proposed}) do
    switches = switch_changes(%{}, proposed)

    %{
      asset(organization_id, mission_id, id, proposed)
      | commanding_enabled: switches[:commanding_enabled],
        telemetry_enabled: switches[:telemetry_enabled]
    }
  end

  defp update(organization_id, mission_id, %{id: id, current: previous, proposed: proposed}) do
    previous = previous || %{}

    %{
      spacecraft: asset(organization_id, mission_id, id, proposed),
      switches: switch_changes(previous, proposed),
      frees_scid?: is_integer(previous["scid"]) and previous["scid"] != proposed["scid"]
    }
  end

  defp actor(op), do: actor_in(Map.get(op.payload, "options"))

  defp actor_in(options), do: Map.get(options || %{}, :actor) || %{"kind" => "change_set"}

  # Archiving (#49/#50, L22): what's still ahead of it, and whether it has had traffic. A new
  # SCID another mission of the organization flies through a shared provider account (ux U81).
  @impl true
  def holds(organization_id, mission_id, entries),
    do:
      ArchiveHolds.holds(organization_id, mission_id, entries) ++
        ScidHolds.holds(organization_id, mission_id, entries)

  @impl true
  def summary(:delete, previous, nil), do: "Archive spacecraft #{previous["display_name"]}"
  def summary(:create, nil, proposed), do: "Add spacecraft #{proposed["display_name"]}"
  def summary(_action, previous, _proposed), do: "Edit spacecraft #{previous["display_name"]}"

  # A switch change rebuilds the runtime (the configuration follows it); identity doesn't.
  @impl true
  def runtime_impact(:update, previous, proposed) when is_map(previous) and is_map(proposed),
    do: if(switch_changes(previous, proposed) == %{}, do: :none, else: :generation)

  def runtime_impact(_action, _previous, _proposed), do: :none

  # Absent or nil leaves a switch as it is (older recorded documents, rollbacks).
  defp switch_errors(document) do
    for key <- @switches,
        not is_nil(document[key]),
        not is_boolean(document[key]),
        do: F.error(key, "Choose on or off")
  end

  # Only switches the change set moves are written: an edit of the name doesn't make the change
  # set the writer of a switch it never touched.
  defp switch_changes(previous, proposed) do
    for key <- @switches,
        Map.has_key?(proposed, key),
        is_boolean(proposed[key]),
        proposed[key] != Map.get(previous, key),
        into: %{},
        do: {String.to_existing_atom(key), proposed[key]}
  end

  defp pin_pair(%{"spacecraft_type_id" => id, "spacecraft_type_version" => version})
       when is_nil(id) == is_nil(version),
       do: []

  defp pin_pair(%{"spacecraft_type_id" => nil, "spacecraft_type_version" => nil}), do: []
  defp pin_pair(document) when not is_map_key(document, "spacecraft_type_id"), do: []

  defp pin_pair(_document),
    do: [F.error("spacecraft_type_version", "Choose a profile and its version together")]

  @impl true
  def stage_conflicts(organization_id, mission_id, staged, prepared),
    do: StagedScids.conflicts(organization_id, mission_id, staged, prepared)

  defp asset(organization_id, mission_id, id, proposed) do
    SpacecraftAsset.new(%{
      spacecraft_id: id,
      organization_id: organization_id,
      mission_id: mission_id,
      display_name: proposed["display_name"],
      scid: proposed["scid"],
      spacecraft_type_id: proposed["spacecraft_type_id"],
      spacecraft_type_version: proposed["spacecraft_type_version"],
      metadata: proposed["metadata"] || %{}
    })
  end

  @doc false
  def document(%SpacecraftAsset{} = spacecraft) do
    %{
      "display_name" => spacecraft.display_name,
      "scid" => spacecraft.scid,
      "spacecraft_type_id" => spacecraft.spacecraft_type_id,
      "spacecraft_type_version" => spacecraft.spacecraft_type_version,
      "metadata" => spacecraft.metadata || %{}
    }
    # A switch is in the document once a change set set it; before that the spacecraft's own
    # configuration decides, and recorded documents from before L22 compare equal.
    |> put_set("commanding_enabled", spacecraft.commanding_enabled)
    |> put_set("telemetry_enabled", spacecraft.telemetry_enabled)
  end

  defp put_set(document, _key, nil), do: document
  defp put_set(document, key, value), do: Map.put(document, key, value)
end
