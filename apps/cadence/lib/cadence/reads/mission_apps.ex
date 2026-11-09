defmodule Cadence.Reads.MissionApps do
  @moduledoc """
  A1, the console's Apps list (Setup rail 08): every application that can be
  installed on a mission, with this mission's installation state.

  - `state`: `installed | disabled | not_installed`. Platform applications are
    always on (`platform: true`) and can't be changed.
  - `permissions`: `apps.install` from the check the install, disable and
    uninstall actions enforce (`ApplicationInstallations`: `:operate_mission`;
    DECISIONS #38).

  The actions stay direct (not a change-set kind): an installation is a
  host lifecycle record, versioned by its own lifecycle events.
  """

  alias Cadence.Applications.{
    ApplicationDefinition,
    ApplicationInstallations,
    HostContext,
    Registry
  }

  alias Cadence.Auth.{Policy, Scope}

  @spec load(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def load(%Scope{} = scope, mission_id) do
    with {:ok, installations} <-
           ApplicationInstallations.list(scope, HostContext.mission(mission_id)) do
      by_key = Map.new(installations, &{&1.application_key, &1})

      {:ok,
       %{
         apps:
           :mission
           |> Registry.available_for_scope()
           |> Enum.map(&row(&1, Map.get(by_key, &1.application_key)))
           |> Enum.sort_by(&{not &1.platform, &1.name}),
         permissions: permissions(scope, mission_id)
       }}
    end
  end

  @doc "One app's row after an action."
  @spec app(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, :app_not_found}
  def app(%Scope{} = scope, mission_id, key) do
    with {:ok, %{apps: apps}} <- load(scope, mission_id) do
      case Enum.find(apps, &(&1.key == key)) do
        nil -> {:error, :app_not_found}
        row -> {:ok, row}
      end
    end
  end

  @spec permissions(Scope.t(), binary()) :: [binary()]
  def permissions(scope, mission_id) do
    params = %{organization_id: scope.organization_id, mission_id: mission_id}
    if Policy.authorize(scope, :operate_mission, params) == :ok, do: ["apps.install"], else: []
  end

  defp row(%ApplicationDefinition{} = definition, installation) do
    platform? = definition.installation_policy == :platform

    state =
      cond do
        platform? -> :installed
        is_nil(installation) -> :not_installed
        true -> state(installation.lifecycle_state)
      end

    %{
      key: definition.application_key,
      name: definition.display_name,
      description: definition.description,
      platform: platform?,
      installed: state == :installed,
      state: state,
      version: if(state != :not_installed, do: installed_version(installation, definition)),
      consequence_if_missing: nil
    }
  end

  defp state(:disabled), do: :disabled
  defp state(:uninstalled), do: :not_installed
  defp state(_active), do: :installed

  defp installed_version(nil, definition), do: definition.version
  defp installed_version(installation, _definition), do: installation.application_version
end
