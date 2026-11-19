defmodule Cadence.ContactPlanning.TemplateTargets do
  @moduledoc """
  Which spacecraft a contact requirement template applies to (DECISIONS #37,
  docs/apogee/domain/contact-templates.md). A version's `target_document` is
  one of:

  - `%{"kind" => "profile", "spacecraft_type_id" => id}`: every spacecraft
    pinned to that profile (any version);
  - `%{"kind" => "plane", "plane" => n}`: spacecraft whose `metadata.plane`
    is the integer `n`. **Interim:** `metadata.plane` is free-form until plane
    is first-class, so a missing or non-integer plane never matches;
  - `%{"kind" => "spacecraft_ids", "spacecraft_ids" => [id, ...]}` (1 to
    10,000, unique).

  Profile and plane targets may add `"exclude_spacecraft_ids"`. Membership
  resolves when materializing, so it follows pins, metadata and new
  spacecraft. `normalize/1` and `select/2` are pure.
  """

  alias Cadence.Persistence.JsonDocument
  alias Cadence.{Spacecraft, SpacecraftStore, SpacecraftTypeStore}

  @max_ids 10_000

  @doc "The legacy single-spacecraft target."
  @spec spacecraft(binary()) :: map()
  def spacecraft(spacecraft_id) when is_binary(spacecraft_id),
    do: %{"kind" => "spacecraft_ids", "spacecraft_ids" => [spacecraft_id]}

  @doc "Normalizes a target document; raises `ArgumentError` on a malformed one."
  @spec normalize!(map()) :: map()
  def normalize!(target) when is_map(target) do
    case normalize(target) do
      {:ok, normalized} -> normalized
      {:error, message} -> raise ArgumentError, "target_document: " <> message
    end
  end

  def normalize!(_target), do: raise(ArgumentError, "target_document must be an object")

  @spec normalize(map()) :: {:ok, map()} | {:error, binary()}
  def normalize(target) when is_map(target) do
    target = JsonDocument.encode(target)

    with {:ok, base} <- kind(target),
         {:ok, excludes} <- excludes(base["kind"], Map.get(target, "exclude_spacecraft_ids")) do
      {:ok, if(excludes == [], do: base, else: Map.put(base, "exclude_spacecraft_ids", excludes))}
    end
  end

  def normalize(_target), do: {:error, "must be an object"}

  @doc "The one spacecraft of a single-spacecraft list, else nil (legacy readers)."
  @spec single(map()) :: binary() | nil
  def single(%{"kind" => "spacecraft_ids", "spacecraft_ids" => [id]}), do: id
  def single(_target), do: nil

  @doc "The ids of `spacecraft` that `target` applies to, in input order (pure)."
  @spec select(map(), [Spacecraft.t()]) :: [binary()]
  def select(target, spacecraft) do
    excluded = MapSet.new(Map.get(target, "exclude_spacecraft_ids", []))

    spacecraft
    |> Enum.filter(&member?(target, &1))
    |> Enum.map(& &1.spacecraft_id)
    |> Enum.reject(&MapSet.member?(excluded, &1))
  end

  @doc "Excluded ids the target wouldn't include anyway (preview says so)."
  @spec excluded_outside(map(), [Spacecraft.t()]) :: [binary()]
  def excluded_outside(target, spacecraft) do
    included = spacecraft |> Enum.filter(&member?(target, &1)) |> MapSet.new(& &1.spacecraft_id)
    target |> Map.get("exclude_spacecraft_ids", []) |> Enum.reject(&MapSet.member?(included, &1))
  end

  @doc "Resolves a target against the mission's spacecraft now."
  @spec resolve(binary(), binary(), map()) :: [binary()]
  def resolve(organization_id, mission_id, target),
    # Sorted by id, so a rename doesn't change a reviewed start's hash.
    do: target |> select(candidates(organization_id, mission_id, target)) |> Enum.sort()

  @doc "The spacecraft a target is evaluated over (profile pins via the store)."
  @spec candidates(binary(), binary(), map()) :: [Spacecraft.t()]
  def candidates(organization_id, mission_id, %{"kind" => "profile", "spacecraft_type_id" => id}),
    do: SpacecraftStore.list_pinned_to_profile(organization_id, mission_id, id)

  def candidates(organization_id, mission_id, _target),
    do: SpacecraftStore.list_spacecraft(organization_id, mission_id)

  @doc "Checks references: the profile exists and every listed or excluded id is a mission spacecraft."
  @spec validate(binary(), binary(), map()) :: :ok | {:error, term()}
  def validate(organization_id, mission_id, target) do
    known =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> MapSet.new(& &1.spacecraft_id)

    ids = Map.get(target, "spacecraft_ids", []) ++ Map.get(target, "exclude_spacecraft_ids", [])

    with :ok <- profile_exists(organization_id, mission_id, target) do
      case Enum.reject(ids, &MapSet.member?(known, &1)) do
        [] -> :ok
        unknown -> {:error, {:template_target_unknown_spacecraft, unknown}}
      end
    end
  end

  defp profile_exists(organization_id, mission_id, %{"kind" => "profile"} = target) do
    case SpacecraftTypeStore.fetch_spacecraft_type(
           organization_id,
           mission_id,
           target["spacecraft_type_id"]
         ) do
      {:ok, _profile} -> :ok
      _missing -> {:error, :template_target_profile_not_found}
    end
  end

  defp profile_exists(_organization_id, _mission_id, _target), do: :ok

  defp member?(%{"kind" => "profile", "spacecraft_type_id" => id}, craft),
    do: craft.spacecraft_type_id == id

  defp member?(%{"kind" => "plane", "plane" => plane}, craft),
    do: (craft.metadata || %{})["plane"] === plane

  defp member?(%{"kind" => "spacecraft_ids", "spacecraft_ids" => ids}, craft),
    do: craft.spacecraft_id in ids

  defp kind(%{"kind" => "profile", "spacecraft_type_id" => id}) when is_binary(id) and id != "",
    do: {:ok, %{"kind" => "profile", "spacecraft_type_id" => id}}

  defp kind(%{"kind" => "profile"}), do: {:error, "a profile target needs spacecraft_type_id"}

  defp kind(%{"kind" => "plane", "plane" => plane}) when is_integer(plane) and plane > 0,
    do: {:ok, %{"kind" => "plane", "plane" => plane}}

  defp kind(%{"kind" => "plane"}), do: {:error, "plane must be a positive integer"}

  defp kind(%{"kind" => "spacecraft_ids", "spacecraft_ids" => ids}) when is_list(ids) do
    cond do
      ids == [] or length(ids) > @max_ids ->
        {:error, "spacecraft_ids needs 1 to #{@max_ids} ids"}

      not Enum.all?(ids, &(is_binary(&1) and &1 != "")) ->
        {:error, "spacecraft_ids must be ids"}

      length(Enum.uniq(ids)) != length(ids) ->
        {:error, "spacecraft_ids must be unique"}

      true ->
        {:ok, %{"kind" => "spacecraft_ids", "spacecraft_ids" => ids}}
    end
  end

  defp kind(_target), do: {:error, "kind must be profile, plane or spacecraft_ids"}

  defp excludes(_kind, nil), do: {:ok, []}
  defp excludes(_kind, []), do: {:ok, []}

  defp excludes("spacecraft_ids", _ids),
    do: {:error, "exclude_spacecraft_ids is only for profile and plane targets"}

  defp excludes(_kind, ids) when is_list(ids) and length(ids) <= @max_ids do
    if Enum.all?(ids, &(is_binary(&1) and &1 != "")),
      do: {:ok, Enum.uniq(ids)},
      else: {:error, "exclude_spacecraft_ids must be ids"}
  end

  defp excludes(_kind, _ids), do: {:error, "exclude_spacecraft_ids must be a list of ids"}
end
