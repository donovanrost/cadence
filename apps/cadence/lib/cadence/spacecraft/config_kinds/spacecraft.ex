defmodule Cadence.Spacecraft.ConfigKinds.Spacecraft do
  @moduledoc """
  Change-set kind for spacecraft identity and profile pin.

  Document: `%{"display_name", "scid", "spacecraft_type_id", "spacecraft_type_version",
  "metadata"}`. Spacecraft can't be removed yet (there is no delete in the store).

  Rules carried over from `Cadence.Spacecraft.Identity`: a pin names an existing, active profile
  version; synthetic configuration profiles can't be chosen; a spacecraft whose framing is
  governed by its configuration review keeps its pin. Identity changes have no direct runtime
  effect: runtime pipelines pick spacecraft configuration up through activation.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Platform.ConfigurationSettings
  alias Cadence.Spacecraft, as: SpacecraftAsset
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftTypeStore

  @fields ~w(display_name scid spacecraft_type_id spacecraft_type_version metadata)
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
    |> Map.new(&{&1.spacecraft_id, document(&1)})
  end

  @impl true
  def normalize(:delete, _id, nil),
    do: {:error, [F.error("", "Spacecraft can't be removed yet")]}

  def normalize(_action, _id, %{} = document) do
    document = Map.put_new(document, "metadata", %{})

    errors =
      F.only(document, @fields) ++
        F.text(document, "display_name", 1..200, required: true, label: "Name") ++
        F.integer(document, "scid", 0..1023, label: "SCID") ++
        F.text(document, "spacecraft_type_id", 1..120, label: "Profile") ++
        F.integer(document, "spacecraft_type_version", 1..1_000_000, label: "Profile version") ++
        F.map(document, "metadata") ++ pin_pair(document)

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the spacecraft details")]}

  @impl true
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
    stored(SpacecraftStore.persist_spacecraft(organization_id, spacecraft))
  end

  def write(organization_id, mission_id, :update, id, _previous, proposed, _options) do
    spacecraft = asset(organization_id, mission_id, id, proposed)
    stored(SpacecraftStore.update_spacecraft(organization_id, spacecraft))
  end

  @impl true
  def summary(:create, nil, proposed), do: "Add spacecraft #{proposed["display_name"]}"
  def summary(_action, previous, _proposed), do: "Edit spacecraft #{previous["display_name"]}"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none

  defp pin_pair(%{"spacecraft_type_id" => id, "spacecraft_type_version" => version})
       when is_nil(id) == is_nil(version),
       do: []

  defp pin_pair(%{"spacecraft_type_id" => nil, "spacecraft_type_version" => nil}), do: []
  defp pin_pair(document) when not is_map_key(document, "spacecraft_type_id"), do: []

  defp pin_pair(_document),
    do: [F.error("spacecraft_type_version", "Choose a profile and its version together")]

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

  defp stored({:ok, spacecraft}), do: {:ok, document(spacecraft), []}
  defp stored({:error, reason}), do: {:error, reason}

  @doc false
  def document(%SpacecraftAsset{} = spacecraft) do
    %{
      "display_name" => spacecraft.display_name,
      "scid" => spacecraft.scid,
      "spacecraft_type_id" => spacecraft.spacecraft_type_id,
      "spacecraft_type_version" => spacecraft.spacecraft_type_version,
      "metadata" => spacecraft.metadata || %{}
    }
  end
end
