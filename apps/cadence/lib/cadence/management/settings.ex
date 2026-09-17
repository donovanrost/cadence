defmodule Cadence.Management.Settings do
  @moduledoc "Settings composition; registered domain owners validate and save their values."
  require Logger
  alias Cadence.Applications.{ApplicationInstallations, Registry}
  alias Cadence.Auth.SettingsAccess
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Platform.ScopedSettings

  def load(scope, mission_id, section_id) do
    with :ok <- SettingsAccess.authorize(scope, :read_settings, mission_id),
         sections = sections(scope.organization_id, mission_id),
         {:ok, selected} <- select(sections, section_id) do
      {:ok,
       %{
         section_id: section_id,
         sections: Enum.map(sections, &Map.delete(&1, :provider)),
         can_edit: SettingsAccess.authorize(scope, :manage_settings, mission_id) == :ok,
         settings: read_section(selected.provider, scope.organization_id, mission_id),
         history: ScopedSettings.history(scope.organization_id, mission_id, section_id)
       }}
    end
  end

  def save(scope, mission_id, section_id, token, input) do
    with :ok <- SettingsAccess.authorize(scope, :manage_settings, mission_id),
         {:ok, selected} <- select(sections(scope.organization_id, mission_id), section_id) do
      save_section(selected.provider, scope, mission_id, token, input)
    end
  end

  defp read_section(provider, organization_id, mission_id) do
    provider.settings_snapshot(organization_id, mission_id)
  rescue
    exception ->
      Logger.error(
        "Settings provider #{inspect(provider)} read failed: #{inspect(exception.__struct__)}"
      )

      nil
  end

  defp save_section(provider, scope, mission_id, token, input) do
    provider.save(scope, mission_id, token, input)
  rescue
    exception ->
      Logger.error(
        "Settings provider #{inspect(provider)} write unconfirmed: #{inspect(exception.__struct__)}"
      )

      {:error, :settings_write_unconfirmed}
  end

  defp select(sections, section_id) do
    case Enum.filter(sections, &(&1.id == section_id)) do
      [section] -> {:ok, section}
      _ -> {:error, :unknown_settings_section}
    end
  end

  defp sections(organization_id, mission_id) do
    scope = if is_nil(mission_id), do: :organization, else: :mission
    installed = ApplicationInstallations.settings_application_keys(organization_id, mission_id)

    governance = %{
      id: "cadence.governance",
      slot: "settings.section",
      version: 1,
      title: "Governance",
      description: "How configuration changes become active.",
      provider: ActivationPolicy,
      scopes: ["organization", "mission"],
      owner: %{kind: "host", label: "Cadence"}
    }

    applications =
      for definition <- Registry.available(),
          definition.installation_policy == :platform or definition.application_key in installed,
          section <- definition.settings_sections,
          scope in section.scopes do
        %{
          id: section.id,
          slot: "settings.section",
          version: 1,
          title: section.title,
          provider: section.provider,
          description: section.description,
          scopes: Enum.map(section.scopes, &to_string/1),
          owner: %{
            kind: "application",
            applicationKey: definition.application_key,
            label: section.title
          }
        }
      end

    admitted =
      applications
      |> Enum.reject(&String.starts_with?(&1.id, "cadence."))
      |> Enum.group_by(& &1.id)
      |> Enum.flat_map(fn {_id, entries} -> if length(entries) == 1, do: entries, else: [] end)
      |> Enum.sort_by(& &1.id)
      |> Enum.take(64)

    [governance | admitted]
  end
end
