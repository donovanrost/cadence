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
  alias Cadence.Platform.ConfigurationSettings
  alias Cadence.Spacecraft, as: SpacecraftAsset
  alias Cadence.Spacecraft.ConfigKinds.{ArchiveHolds, ScidHolds}
  alias Cadence.Spacecraft.StagedScids
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftTypeStore

  @switches ~w(commanding_enabled telemetry_enabled)
  @fields ~w(display_name scid spacecraft_type_id spacecraft_type_version metadata) ++ @switches
  @governed_key "spacecraft_configuration_revision_id"
  @synthetic_prefix "spacecraft_configuration_profile_"
  @pin_keys ["spacecraft_type_id", "spacecraft_type_version"]

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

  def validate(organization_id, mission_id, _action, _entity_id, previous, proposed) do
    errors =
      scid_free(organization_id, mission_id, previous, proposed) ++
        pin_exists(organization_id, mission_id, previous, proposed) ++
        governed_rule(organization_id, mission_id, previous, proposed)

    if errors == [], do: :ok, else: {:error, errors}
  end

  @impl true
  def write(organization_id, mission_id, :create, id, nil, proposed, _options) do
    spacecraft = asset(organization_id, mission_id, id, proposed)

    with {:ok, created} <- SpacecraftStore.persist_spacecraft(organization_id, spacecraft) do
      organization_id
      |> put_switches(mission_id, id, %{}, proposed, created)
      |> stored(organization_id, mission_id)
    end
  end

  def write(organization_id, mission_id, :update, id, previous, proposed, _options) do
    spacecraft = asset(organization_id, mission_id, id, proposed)

    with {:ok, updated} <- SpacecraftStore.update_spacecraft(organization_id, spacecraft) do
      organization_id
      |> put_switches(mission_id, id, previous || %{}, proposed, updated)
      |> stored(organization_id, mission_id)
    end
  end

  def write(organization_id, mission_id, :delete, id, _previous, nil, options) do
    actor = Map.get(options || %{}, :actor) || %{"kind" => "change_set"}

    case SpacecraftStore.archive_spacecraft(organization_id, mission_id, id, actor) do
      {:ok, _archived} -> {:ok, nil, []}
      {:error, reason} -> {:error, reason}
    end
  end

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

  defp put_switches(organization_id, mission_id, id, previous, proposed, written) do
    case switch_changes(previous, proposed) do
      changes when changes == %{} -> {:ok, written}
      changes -> SpacecraftStore.put_switches(organization_id, mission_id, id, changes)
    end
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

  defp scid_free(_organization_id, _mission_id, _previous, %{"scid" => nil}), do: []

  defp scid_free(_organization_id, _mission_id, %{"scid" => scid}, %{"scid" => scid}), do: []

  defp scid_free(organization_id, mission_id, _previous, %{"scid" => scid}) do
    if SpacecraftStore.scid_taken?(organization_id, mission_id, scid),
      do: [F.error("scid", "SCID #{scid} is already used in this mission")],
      else: []
  end

  defp scid_free(_organization_id, _mission_id, _previous, _proposed), do: []

  defp pin_exists(_organization_id, _mission_id, _previous, %{"spacecraft_type_id" => nil}),
    do: []

  defp pin_exists(organization_id, mission_id, previous, %{"spacecraft_type_id" => id} = doc) do
    cond do
      same_pin?(previous, doc) ->
        []

      String.starts_with?(id, @synthetic_prefix) ->
        [F.error("spacecraft_type_id", "Choose a shared profile")]

      match?(
        {:ok, %{lifecycle_state: :active}},
        SpacecraftTypeStore.fetch_spacecraft_type_version(
          organization_id,
          mission_id,
          id,
          doc["spacecraft_type_version"]
        )
      ) ->
        []

      true ->
        [F.error("spacecraft_type_id", "That profile version doesn't exist")]
    end
  end

  defp pin_exists(_organization_id, _mission_id, _previous, _proposed), do: []

  # With profile framing generations on, the profile takes framing authority, so a spacecraft
  # configured through per-spacecraft review may be re-pinned (DECISIONS #33).
  defp governed_rule(organization_id, mission_id, previous, proposed) do
    if ConfigurationSettings.profile_framing_generations?(organization_id, mission_id),
      do: governed_key_kept(previous && get_in(previous, ["metadata", @governed_key]), proposed),
      else: governed(previous, proposed)
  end

  defp same_pin?(nil, _proposed), do: false

  defp same_pin?(previous, proposed),
    do: Map.take(previous, @pin_keys) == Map.take(proposed, @pin_keys)

  defp governed(%{"metadata" => %{@governed_key => revision}} = previous, proposed)
       when is_binary(revision) do
    errors =
      if same_pin?(previous, proposed),
        do: [],
        else: [
          F.error(
            "spacecraft_type_id",
            "Change framing in Communications and submit it for review"
          )
        ]

    errors ++ governed_key_kept(revision, proposed)
  end

  defp governed(_previous, proposed), do: governed_key_kept(nil, proposed)

  defp governed_key_kept(revision, proposed) do
    if get_in(proposed, ["metadata", @governed_key]) == revision,
      do: [],
      else: [F.error("metadata", "#{@governed_key} is managed by configuration review")]
  end

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

  defp stored({:ok, spacecraft}, _organization_id, _mission_id),
    do: {:ok, document(spacecraft), []}

  defp stored({:error, reason}, _organization_id, _mission_id), do: {:error, reason}

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
