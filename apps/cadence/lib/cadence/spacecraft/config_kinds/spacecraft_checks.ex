defmodule Cadence.Spacecraft.ConfigKinds.SpacecraftChecks do
  @moduledoc """
  What the spacecraft kind refuses in a change (#1049): a SCID the mission already uses, a profile
  version that doesn't exist or can't be chosen, the governed-pin rule.

  The answers come from a context read once for the whole batch of changes (the profile-framing
  setting, the holders of the SCIDs asked for, the active profile versions asked for), so a
  fleet of any size costs the same reads. `check/2` walks the changes in order and the context
  follows: a SCID an earlier change took or freed counts for the next, as it did when each change
  was written before the next was checked.
  """

  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Platform.ConfigurationSettings
  alias Cadence.SpacecraftStore.Bulk
  alias Cadence.SpacecraftTypeStore

  @governed_key "spacecraft_configuration_revision_id"
  @synthetic_prefix "spacecraft_configuration_profile_"
  @pin_keys ["spacecraft_type_id", "spacecraft_type_version"]

  @enforce_keys [:framing?, :scids, :profiles]
  defstruct [:framing?, :scids, :profiles]

  @typedoc "A change as the pipeline hands it over: `action`, `id`, `current`, `proposed`."
  @type change :: %{
          required(:action) => :create | :update | :delete,
          required(:id) => binary(),
          required(:current) => map() | nil,
          required(:proposed) => map() | nil,
          optional(atom()) => term()
        }

  @type t :: %__MODULE__{
          framing?: boolean(),
          scids: %{non_neg_integer() => binary()},
          profiles: MapSet.t({binary(), pos_integer()})
        }

  @doc "The reads the checks of `changes` need, once."
  @spec context(binary(), binary(), [change()]) :: t()
  def context(organization_id, mission_id, changes) do
    written = Enum.reject(changes, &(&1.action == :delete))

    %__MODULE__{
      framing?:
        written != [] and
          ConfigurationSettings.profile_framing_generations?(organization_id, mission_id),
      scids:
        Bulk.scid_holders(
          organization_id,
          mission_id,
          for(%{proposed: %{"scid" => scid}} <- written, is_integer(scid), do: scid)
        ),
      profiles: active_profiles(organization_id, mission_id, written)
    }
  end

  @doc "The field errors of `change` (empty: it passes) and the context after it."
  @spec check(t(), change()) :: {[map()], t()}
  def check(%__MODULE__{} = context, %{action: :delete}), do: {[], context}

  def check(%__MODULE__{} = context, %{id: id, current: previous, proposed: proposed}) do
    errors =
      scid_errors(context, previous, proposed) ++
        pin_errors(context, previous, proposed) ++ governed_errors(context, previous, proposed)

    if errors == [], do: {[], take_scid(context, id, previous, proposed)}, else: {errors, context}
  end

  # A SCID is taken by anyone who holds it (archived spacecraft keep theirs); keeping your own is
  # not a change.
  defp scid_errors(_context, _previous, %{"scid" => nil}), do: []
  defp scid_errors(_context, %{"scid" => scid}, %{"scid" => scid}), do: []

  defp scid_errors(context, _previous, %{"scid" => scid}) do
    if Map.has_key?(context.scids, scid),
      do: [F.error("scid", "SCID #{scid} is already used in this mission")],
      else: []
  end

  defp scid_errors(_context, _previous, _proposed), do: []

  defp take_scid(context, id, previous, proposed) do
    scids =
      context.scids
      |> release(id, previous)
      |> claim(id, proposed)

    %{context | scids: scids}
  end

  defp release(scids, id, %{"scid" => scid}) when is_integer(scid) do
    if scids[scid] == id, do: Map.delete(scids, scid), else: scids
  end

  defp release(scids, _id, _previous), do: scids

  defp claim(scids, id, %{"scid" => scid}) when is_integer(scid), do: Map.put(scids, scid, id)
  defp claim(scids, _id, _proposed), do: scids

  defp pin_errors(_context, _previous, %{"spacecraft_type_id" => nil}), do: []

  defp pin_errors(context, previous, %{"spacecraft_type_id" => id} = proposed) do
    cond do
      same_pin?(previous, proposed) ->
        []

      String.starts_with?(id, @synthetic_prefix) ->
        [F.error("spacecraft_type_id", "Choose a shared profile")]

      MapSet.member?(context.profiles, {id, proposed["spacecraft_type_version"]}) ->
        []

      true ->
        [F.error("spacecraft_type_id", "That profile version doesn't exist")]
    end
  end

  defp pin_errors(_context, _previous, _proposed), do: []

  # The active profile versions the changes name and haven't just kept: one read for all of them.
  defp active_profiles(organization_id, mission_id, written) do
    references =
      for %{current: previous, proposed: %{"spacecraft_type_id" => id} = proposed} <- written,
          is_binary(id),
          not String.starts_with?(id, @synthetic_prefix),
          not same_pin?(previous, proposed),
          is_integer(proposed["spacecraft_type_version"]),
          do: {id, proposed["spacecraft_type_version"]}

    {:ok, found} =
      SpacecraftTypeStore.fetch_spacecraft_type_versions_in_batches(
        organization_id,
        mission_id,
        references
      )

    for {reference, %{lifecycle_state: :active}} <- found, into: MapSet.new(), do: reference
  end

  # With profile framing generations on, the profile takes framing authority, so a spacecraft
  # configured through per-spacecraft review may be re-pinned (DECISIONS #33).
  defp governed_errors(%__MODULE__{framing?: true}, previous, proposed),
    do: governed_key_kept(previous && get_in(previous, ["metadata", @governed_key]), proposed)

  defp governed_errors(%__MODULE__{framing?: false}, previous, proposed),
    do: governed(previous, proposed)

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
end
