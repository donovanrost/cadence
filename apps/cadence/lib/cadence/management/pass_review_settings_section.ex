defmodule Cadence.Management.PassReviewSettingsSection do
  @moduledoc """
  Settings provider for `cadence.pass_review` (`Cadence.Platform.PassReviewSettings`), so
  Settings (ST1) can read and edit the pass realized threshold and the realization target.
  Lives in management because authorizing needs `SettingsAccess`.
  """

  @behaviour Cadence.Applications.SettingsProvider

  alias Cadence.Auth.SettingsAccess
  alias Cadence.Platform.{PassReviewSettings, ScopedSettings}

  @impl true
  def settings_snapshot(organization_id, mission_id),
    do: PassReviewSettings.load(organization_id, mission_id)

  @impl true
  def save(scope, mission_id, token, input) do
    with :ok <- SettingsAccess.authorize(scope, :manage_settings, mission_id),
         {:ok, document} <- decode(mission_id, input) do
      ScopedSettings.save(
        scope.organization_id,
        mission_id,
        PassReviewSettings.section_id(),
        PassReviewSettings.default(),
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

  defp value(%{} = value) do
    if map_size(value) > 0 and Map.keys(value) -- PassReviewSettings.keys() == [] and
         Enum.all?(value, fn {_key, share} -> is_number(share) and share > 0 and share <= 1 end),
       do: :ok,
       else: {:error, :invalid_settings}
  end

  defp value(_value), do: {:error, :invalid_settings}
end
