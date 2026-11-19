defmodule Cadence.Management.ConfigurationSettingsSection do
  @moduledoc """
  Settings provider for scoped section `cadence.configuration`
  (`Cadence.Platform.ConfigurationSettings`, the profile framing generations
  flag), so the console's Settings (ST1) can read and edit it. It lives in
  management because authorizing needs `SettingsAccess` (platform can't
  depend on identity).
  """

  @behaviour Cadence.Applications.SettingsProvider

  alias Cadence.Auth.SettingsAccess
  alias Cadence.Platform.{ConfigurationSettings, ScopedSettings}

  # Kept equal to ConfigurationSettings' default (on since DECISIONS #45).
  @default %{"value" => %{"profile_framing_generations" => true}, "allow_override" => true}

  @impl true
  def settings_snapshot(organization_id, mission_id),
    do:
      ScopedSettings.load(
        organization_id,
        mission_id,
        ConfigurationSettings.section_id(),
        @default
      )

  @impl true
  def save(scope, mission_id, token, input) do
    with :ok <- SettingsAccess.authorize(scope, :manage_settings, mission_id),
         {:ok, document} <- decode(mission_id, input) do
      ScopedSettings.save(
        scope.organization_id,
        mission_id,
        ConfigurationSettings.section_id(),
        @default,
        token,
        document,
        SettingsAccess.actor(scope)
      )
    end
  end

  defp decode(nil, %{"value" => value, "allow_override" => allowed} = input)
       when map_size(input) == 2 and is_boolean(allowed) do
    with :ok <- value(value), do: {:ok, input}
  end

  defp decode(mission, %{"value" => nil} = input)
       when is_binary(mission) and map_size(input) == 1,
       do: {:ok, input}

  defp decode(mission, %{"value" => value} = input)
       when is_binary(mission) and map_size(input) == 1 do
    with :ok <- value(value), do: {:ok, input}
  end

  defp decode(_mission, _input), do: {:error, :invalid_settings}

  defp value(%{"profile_framing_generations" => on} = value)
       when map_size(value) == 1 and is_boolean(on),
       do: :ok

  defp value(_value), do: {:error, :invalid_settings}
end
