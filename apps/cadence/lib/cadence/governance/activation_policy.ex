defmodule Cadence.Governance.ActivationPolicy do
  @moduledoc "Organization approval requirements, mission overrides, and exact policy evidence."
  alias Cadence.Auth.SettingsAccess
  alias Cadence.Missions
  alias Cadence.Platform.ScopedSettings

  @behaviour Cadence.Applications.SettingsProvider
  @section "cadence.governance"
  def section_id, do: @section

  def load(organization_id, mission_id),
    do: ScopedSettings.load(organization_id, mission_id, @section, default())

  def with_lock(organization_id, operation),
    do: ScopedSettings.with_lock(organization_id, @section, operation)

  def settings_snapshot(organization_id, nil) do
    missions = Missions.settings_overview(organization_id)

    snapshots =
      ScopedSettings.load_many(
        organization_id,
        [nil | Enum.map(missions.items, & &1.id)],
        @section,
        default()
      )

    Map.fetch!(snapshots, nil)
    |> Map.put(:missions_total, missions.total)
    |> Map.put(
      :missions,
      Enum.map(missions.items, fn mission ->
        Map.put(mission, :override, Map.fetch!(snapshots, mission.id).saved)
      end)
    )
  end

  def settings_snapshot(organization_id, mission_id), do: load(organization_id, mission_id)

  def save(scope, mission_id, token, input) do
    with :ok <- SettingsAccess.authorize(scope, :manage_settings, mission_id),
         {:ok, document} <- decode(mission_id, input) do
      ScopedSettings.save(
        scope.organization_id,
        mission_id,
        @section,
        default(),
        token,
        document,
        SettingsAccess.actor(scope)
      )
    end
  end

  def evidence(organization_id, mission_id) do
    current = load(organization_id, mission_id)
    required = current.effective["approval_requirement"] == "independent"

    %{
      "policy" => "scoped_activation_approvals_v1",
      "settings_token" => current.token,
      "approval_required" => required,
      "required_human_approvals" => if(required, do: 1, else: 0),
      "separation_of_duties" => required
    }
  end

  def current?(organization_id, mission_id, policy),
    do: policy == evidence(organization_id, mission_id)

  def validate(organization_id, mission_id, policy) do
    if current?(organization_id, mission_id, policy),
      do: :ok,
      else: {:error, :activation_policy_changed}
  end

  defp default do
    required =
      Application.get_env(:cadence, :activation_governance, [])
      |> Keyword.get(:approval_required, true)

    %{
      "value" => %{"approval_requirement" => if(required, do: "independent", else: "direct")},
      "allow_override" => true
    }
  end

  defp decode(nil, %{"value" => value, "allow_override" => allowed} = input)
       when map_size(input) == 2 and is_boolean(allowed) do
    with :ok <- value(value),
         true <- allowed or value["approval_requirement"] == "independent" do
      {:ok, input}
    else
      _ -> {:error, :invalid_settings}
    end
  end

  defp decode(mission, %{"value" => nil} = input)
       when is_binary(mission) and map_size(input) == 1, do: {:ok, input}

  defp decode(mission, %{"value" => value} = input)
       when is_binary(mission) and map_size(input) == 1 do
    with :ok <- value(value), do: {:ok, input}
  end

  defp decode(_, _), do: {:error, :invalid_settings}

  defp value(%{"approval_requirement" => requirement} = value)
       when map_size(value) == 1 and requirement in ["direct", "independent"], do: :ok

  defp value(_), do: {:error, :invalid_settings}
end
