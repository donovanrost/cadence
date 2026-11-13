defmodule Cadence.Control.SpacecraftOps do
  @moduledoc """
  Console rules for staged `spacecraft` ops (§11 L17, lead and fe-setup), applied before
  staging or previewing. A create carries a `document`; an update carries `changes`
  (`[%{"path", "value"}]`).

  - A switch (`commanding_enabled`, `telemetry_enabled`) left unchanged is **absent**. An explicit
    `null` is a 422, so a client that nulls one by mistake isn't silently ignored.
  - A profile given without a version means that profile's latest version (the domain wants the
    pair; people pick a profile). A version without a profile stays the domain's 422. To keep
    the current pin, leave both out.
  """

  alias Cadence.SpacecraftTypeStore

  @switches ~w(commanding_enabled telemetry_enabled)
  @null "can't be null; leave it out to keep it unchanged"

  @spec prepare(binary(), binary(), [map()]) :: {:ok, [map()]} | {:error, map()}
  def prepare(organization_id, mission_id, ops) when is_list(ops) do
    indexed = Enum.with_index(ops)

    errors =
      for {op, index} <- indexed, key <- null_switches(op), into: %{}, do: {key.(index), @null}

    if errors == %{},
      do: {:ok, Enum.map(ops, &latest_version(organization_id, mission_id, &1))},
      else: {:error, errors}
  end

  defp null_switches(%{kind: "spacecraft", action: "create", document: %{} = document}) do
    for key <- @switches,
        Map.has_key?(document, key) and is_nil(document[key]),
        do: &"ops.#{&1}.document.#{key}"
  end

  defp null_switches(%{kind: "spacecraft", action: "update", changes: changes})
       when is_list(changes) do
    for %{"path" => path, "value" => nil} <- changes,
        path in @switches,
        do: &"ops.#{&1}.changes.#{path}"
  end

  defp null_switches(_op), do: []

  defp latest_version(
         org,
         mission,
         %{kind: "spacecraft", action: "create", document: %{} = doc} = op
       ) do
    case missing_version(org, mission, doc["spacecraft_type_id"], doc["spacecraft_type_version"]) do
      nil -> op
      version -> put_in(op, [:document, "spacecraft_type_version"], version)
    end
  end

  defp latest_version(
         org,
         mission,
         %{kind: "spacecraft", action: "update", changes: changes} = op
       )
       when is_list(changes) do
    values = for %{"path" => path} = change <- changes, into: %{}, do: {path, change["value"]}

    case missing_version(
           org,
           mission,
           values["spacecraft_type_id"],
           values["spacecraft_type_version"]
         ) do
      nil ->
        op

      version ->
        kept = Enum.reject(changes, &match?(%{"path" => "spacecraft_type_version"}, &1))
        %{op | changes: kept ++ [%{"path" => "spacecraft_type_version", "value" => version}]}
    end
  end

  defp latest_version(_org, _mission, op), do: op

  defp missing_version(org, mission, id, nil) when is_binary(id) do
    case SpacecraftTypeStore.fetch_spacecraft_type(org, mission, id) do
      {:ok, profile} -> profile.version
      {:error, _unknown} -> nil
    end
  end

  defp missing_version(_org, _mission, _id, _version), do: nil
end
