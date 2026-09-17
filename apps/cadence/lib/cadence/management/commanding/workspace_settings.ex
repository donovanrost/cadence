defmodule Cadence.Management.Commanding.WorkspaceSettings do
  @moduledoc "Commanding-owned defaults for the initial command workspace layout."
  alias Cadence.Auth.SettingsAccess
  alias Cadence.Platform.ScopedSettings
  @behaviour Cadence.Applications.SettingsProvider
  @section "commanding.defaults"
  @default %{"value" => %{"shelf" => "expanded"}, "allow_override" => true}

  def load(organization_id, mission_id),
    do: ScopedSettings.load(organization_id, mission_id, @section, @default)

  def settings_snapshot(org, mission), do: load(org, mission)

  def save(scope, mission_id, token, input) do
    with :ok <- SettingsAccess.authorize(scope, :manage_settings, mission_id),
         {:ok, document} <- decode(mission_id, input) do
      ScopedSettings.save(
        scope.organization_id,
        mission_id,
        @section,
        @default,
        token,
        document,
        SettingsAccess.actor(scope)
      )
    end
  end

  defp decode(nil, %{"value" => value, "allow_override" => true} = input)
       when map_size(input) == 2 do
    with :ok <- value(value), do: {:ok, input}
  end

  defp decode(mission, %{"value" => nil} = input)
       when is_binary(mission) and map_size(input) == 1, do: {:ok, input}

  defp decode(mission, %{"value" => value} = input)
       when is_binary(mission) and map_size(input) == 1 do
    with :ok <- value(value), do: {:ok, input}
  end

  defp decode(_, _), do: {:error, :invalid_settings}

  defp value(%{"shelf" => shelf} = value)
       when map_size(value) == 1 and shelf in ["expanded", "minimized"], do: :ok

  defp value(_), do: {:error, :invalid_settings}
end
