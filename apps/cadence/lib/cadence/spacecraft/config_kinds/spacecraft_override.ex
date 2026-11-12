defmodule Cadence.Spacecraft.ConfigKinds.SpacecraftOverride do
  @moduledoc """
  Change-set kind for a spacecraft's overrides of its profile (P3).

  Entity: the spacecraft. Document: `%{key => %{"value" => term, "reason" => text}}`, where the
  key is the overridden path with `.` written as `/` (`"frame_parameters/frame_size"`,
  `"routing/ttc/excluded_stations"`), so each override is one document key. An update changes
  keys: a map sets the override, `nil` resets it to the profile value. Route effects are
  derived after apply by the routes kind.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Spacecraft.ConfigKinds.SpacecraftProfile
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Overrides

  @impl true
  def kind, do: "spacecraft_override"

  @impl true
  def id_prefix, do: "spacecraft"

  @doc "The document key for an override path."
  @spec key(String.t()) :: String.t()
  def key(path), do: String.replace(path, ".", "/")

  @doc "The override path for a document key."
  @spec path(String.t()) :: String.t()
  def path(key), do: String.replace(key, "/", ".")

  @impl true
  def load(organization_id, mission_id, ids) do
    {:ok, existing} =
      SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, ids)

    overrides = Overrides.list(organization_id, mission_id, Map.keys(existing))

    Map.new(existing, fn {id, _spacecraft} ->
      {id,
       overrides
       |> Map.get(id, %{})
       |> Map.new(fn {path, o} -> {key(path), %{"value" => o.value, "reason" => o.reason}} end)}
    end)
  end

  @impl true
  def normalize(:update, _id, %{} = document) do
    document = Map.reject(document, fn {_key, value} -> is_nil(value) end)

    errors =
      Enum.flat_map(document, fn {key, value} ->
        cond do
          not Overrides.overridable?(path(key)) ->
            [F.error(key, "#{path(key)} can't be overridden")]

          not (is_map(value) and Map.has_key?(value, "value")) ->
            [F.error(key, "Give the override a value")]

          true ->
            F.text(value, "reason", 1..500, label: "Reason")
            |> Enum.map(&%{&1 | path: key <> ".reason"})
        end
      end)

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Overrides are changed on an existing spacecraft")]}

  @impl true
  # DECISIONS #36/#65: a catalog override moves the spacecraft's catalog through a generation;
  # it must name a catalog revision that exists.
  def validate(organization_id, mission_id, _action, _entity_id, _previous, proposed)
      when is_map(proposed) do
    errors =
      Enum.flat_map(proposed, fn {key, value} ->
        with "catalog_revision_id" <- path(key),
             %{"value" => catalog} when is_binary(catalog) <- value,
             {:error, errors} <-
               SpacecraftProfile.catalog_exists(organization_id, mission_id, catalog, key) do
          errors
        else
          _ok -> []
        end
      end)

    if errors == [], do: :ok, else: {:error, errors}
  end

  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

  @impl true
  def write(organization_id, mission_id, :update, id, previous, proposed, _options) do
    previous = previous || %{}
    # A reset arrives as a key patched to nil.
    proposed = Map.reject(proposed, fn {_key, value} -> is_nil(value) end)

    for {key, _} <- previous, not Map.has_key?(proposed, key) do
      Overrides.delete(organization_id, mission_id, id, path(key))
    end

    Enum.reduce_while(proposed, {:ok, proposed, []}, fn {key, override}, acc ->
      if Map.get(previous, key) == override,
        do: {:cont, acc},
        else: put_override(organization_id, mission_id, id, key, override, acc)
    end)
  end

  defp put_override(organization_id, mission_id, id, key, override, acc) do
    attrs = %{reason: override["reason"]}

    case Overrides.put(organization_id, mission_id, id, path(key), override["value"], attrs) do
      {:ok, _} -> {:cont, acc}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  @impl true
  def summary(_action, previous, proposed) do
    previous = previous || %{}
    added = Map.keys(proposed || %{}) -- Map.keys(previous)
    removed = Map.keys(previous) -- Map.keys(proposed || %{})

    case {added, removed} do
      {[], [key | _]} -> "Reset #{path(key)} to the profile"
      {[key | _], _} -> "Override #{path(key)}"
      _ -> "Change overrides"
    end
  end

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none
end
