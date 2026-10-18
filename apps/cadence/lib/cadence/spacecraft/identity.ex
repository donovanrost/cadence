defmodule Cadence.Spacecraft.Identity do
  @moduledoc "Scoped spacecraft identity changes independent of frontend release delivery."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.{Missions, Spacecraft, SpacecraftStore, SpacecraftTypeStore}

  def action(
        %Scope{mission_id: scoped_mission_id} = scope,
        mission_id,
        spacecraft_id,
        event,
        input
      )
      when event in ["validate", "save"] and is_binary(mission_id) and
             (is_nil(scoped_mission_id) or scoped_mission_id == mission_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, attrs} <- fields(input) do
      with_current(
        scope.organization_id,
        mission_id,
        spacecraft_id,
        &apply_fields(event, scope.organization_id, mission_id, &1, attrs)
      )
    end
  end

  def action(_scope, _mission_id, _spacecraft_id, _event, _input),
    do: {:error, :invalid_spacecraft_action}

  defp apply_fields(event, organization_id, mission_id, current, attrs) do
    with {:ok, binding} <- binding(organization_id, mission_id, current, attrs) do
      complete(event, organization_id, mission_id, current, Map.merge(attrs, binding))
    end
  end

  defp with_current(_organization_id, _mission_id, nil, operation), do: operation.(nil)

  defp with_current(organization_id, mission_id, spacecraft_id, operation),
    do:
      SpacecraftStore.with_locked_spacecraft(
        organization_id,
        mission_id,
        spacecraft_id,
        operation
      )

  defp fields(%{"spacecraft" => attrs}) when is_map(attrs) do
    with {:ok, name} <- name(attrs["display_name"]),
         {:ok, scid} <- scid(attrs["scid"]),
         {:ok, profile_id} <- profile_id(attrs["spacecraft_type_id"]),
         {:ok, version} <- version(Map.get(attrs, "spacecraft_type_version", :unspecified)) do
      {:ok,
       %{
         display_name: name,
         scid: scid,
         spacecraft_type_id: profile_id,
         spacecraft_type_version: version
       }}
    end
  end

  defp fields(_input), do: invalid("display_name", "Enter valid spacecraft details.")

  defp name(value) when is_binary(value) and byte_size(value) <= 255 do
    if String.valid?(value) and String.trim(value) != "",
      do: {:ok, String.trim(value)},
      else: invalid("display_name", "Enter a display name.")
  end

  defp name(_value), do: invalid("display_name", "Enter a display name within 255 bytes.")

  defp scid(value) when value in [nil, ""], do: {:ok, nil}
  defp scid(value) when is_integer(value) and value in 0..1023, do: {:ok, value}

  defp scid(value) when is_binary(value) and byte_size(value) <= 10 do
    case Integer.parse(value) do
      {integer, ""} when integer in 0..1023 -> {:ok, integer}
      _ -> invalid("scid", "Enter a whole number from 0 to 1023, or leave blank.")
    end
  end

  defp scid(_value), do: invalid("scid", "Enter a whole number from 0 to 1023, or leave blank.")

  defp profile_id(value) when value in [nil, ""], do: {:ok, nil}

  defp profile_id(value) when is_binary(value) and byte_size(value) in 1..255 do
    if Regex.match?(~r/^[A-Za-z0-9_-]+$/, value), do: {:ok, value}, else: invalid_profile()
  end

  defp profile_id(_value), do: invalid_profile()

  defp version(value) when value in [nil, "", :unspecified], do: {:ok, value}
  defp version(value) when is_integer(value) and value in 1..2_147_483_647, do: {:ok, value}

  defp version(value) when is_binary(value) and byte_size(value) <= 10 do
    case Integer.parse(value) do
      {integer, ""} when integer in 1..2_147_483_647 -> {:ok, integer}
      _ -> invalid_profile()
    end
  end

  defp version(_value), do: invalid_profile()

  defp binding(_organization_id, _mission_id, %{metadata: metadata} = current, attrs)
       when is_map_key(metadata, "spacecraft_configuration_revision_id") do
    if attrs.spacecraft_type_id == current.spacecraft_type_id and
         attrs.spacecraft_type_version in [current.spacecraft_type_version, :unspecified] do
      {:ok, Map.take(current, [:spacecraft_type_id, :spacecraft_type_version])}
    else
      invalid("spacecraft_type_id", "Change framing in Communications and submit it for review.")
    end
  end

  defp binding(_organization_id, _mission_id, _current, %{
         spacecraft_type_id: nil,
         spacecraft_type_version: version
       })
       when version in [nil, "", :unspecified],
       do: {:ok, %{spacecraft_type_id: nil, spacecraft_type_version: nil}}

  defp binding(organization_id, mission_id, current, %{
         spacecraft_type_id: id,
         spacecraft_type_version: version
       })
       when is_binary(id) do
    with {:ok, version} <- selected_version(organization_id, mission_id, current, id, version),
         {:ok, %{lifecycle_state: :active}} <-
           SpacecraftTypeStore.fetch_spacecraft_type_version(
             organization_id,
             mission_id,
             id,
             version
           ),
         :ok <- admit_binding(organization_id, mission_id, current, id, version) do
      {:ok, %{spacecraft_type_id: id, spacecraft_type_version: version}}
    else
      _ -> invalid_profile()
    end
  end

  defp binding(_organization_id, _mission_id, _current, _attrs), do: invalid_profile()

  # Older remote callers omit the version. Preserve their current pin on identity-only
  # edits; selecting a different profile resolves once, within this authorized action.
  defp selected_version(
         _organization_id,
         _mission_id,
         %{spacecraft_type_id: id, spacecraft_type_version: version},
         id,
         :unspecified
       ),
       do: {:ok, version}

  defp selected_version(organization_id, mission_id, _current, id, :unspecified) do
    with {:ok, profile} <-
           SpacecraftTypeStore.fetch_spacecraft_type(organization_id, mission_id, id),
         do: {:ok, profile.version}
  end

  defp selected_version(_organization_id, _mission_id, _current, _id, version)
       when is_integer(version), do: {:ok, version}

  defp selected_version(_organization_id, _mission_id, _current, _id, _version),
    do: invalid_profile()

  defp admit_binding(
         _organization_id,
         _mission_id,
         %{spacecraft_type_id: id, spacecraft_type_version: version},
         id,
         version
       ),
       do: :ok

  defp admit_binding(organization_id, mission_id, _current, id, _version) do
    with {:ok, active} <-
           SpacecraftTypeStore.fetch_spacecraft_type(organization_id, mission_id, id),
         false <- Map.has_key?(active.metadata, "spacecraft_configuration_revision_id"),
         do: :ok
  end

  defp complete("validate", _organization_id, _mission_id, _current, _attrs),
    do: {:ok, %{"valid" => true}}

  defp complete("save", organization_id, mission_id, current, attrs) do
    result =
      case current do
        nil ->
          SpacecraftStore.persist_spacecraft(
            organization_id,
            Spacecraft.new(Map.put(attrs, :mission_id, mission_id))
          )

        %Spacecraft{} ->
          SpacecraftStore.update_spacecraft(organization_id, struct(current, attrs))
      end

    case result do
      {:ok, saved} ->
        {:ok,
         %{
           "spacecraftId" => saved.spacecraft_id,
           "displayName" => saved.display_name,
           "href" => "/missions/#{mission_id}/spacecraft"
         }}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset_errors(changeset)}

      {:error, _reason} = error ->
        error
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, text ->
        String.replace(text, "%{#{key}}", to_string(value))
      end)
    end)
    |> Map.take([:display_name, :scid, :spacecraft_type_id, :spacecraft_type_version])
    |> Map.new(fn {key, errors} -> {to_string(key), errors} end)
  end

  defp invalid_profile,
    do: invalid("spacecraft_type_id", "Select an available profile version, or choose None.")

  defp invalid(field, message), do: {:error, %{field => [message]}}
end
