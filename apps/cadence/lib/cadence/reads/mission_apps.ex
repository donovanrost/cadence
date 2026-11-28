defmodule Cadence.Reads.MissionApps do
  @moduledoc """
  A1, the console's Apps list (Setup rail 08): every application that can be
  installed on a mission, with this mission's installation state.

  - `state`: `installed | disabled | not_installed`.
  - `version` / `available_version` / `update_available`: the installed version, the
    version this deployment ships, and whether the shipped one is newer (the server
    decides; clients never compare versions). `available_version` is set for every
    row; `version` only once installed.
  - `spacecraft_count`: how many spacecraft the installation covers (the mission's
    active spacecraft; 1 at a spacecraft scope), counted in SQL.
  - `permissions`: `apps.install` from the check the install, disable and
    uninstall actions enforce (`ApplicationInstallations`: `:operate_mission`;
    DECISIONS #38).
  - `status` (`Cadence.Reads.AppStatus`): the app's status at this scope.

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
  alias Cadence.Reads.AppStatus
  alias Cadence.SpacecraftStore

  @spec load(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def load(%Scope{} = scope, mission_id),
    do: load_at(scope, mission_id, HostContext.mission(mission_id))

  @doc """
  The apps at a host context (L19): `HostContext.mission/1`, or `HostContext.spacecraft/2` for
  the apps installable on one spacecraft, with that spacecraft's installations.
  """
  @spec load_at(Scope.t(), binary(), HostContext.t()) :: {:ok, map()} | {:error, term()}
  def load_at(%Scope{} = scope, mission_id, context) do
    level = context.placement

    with {:ok, installations} <- ApplicationInstallations.list(scope, context) do
      by_key = Map.new(installations, &{&1.application_key, &1})

      {:ok,
       %{
         apps:
           level
           |> Registry.available_for_scope()
           |> Enum.map(&row(scope, context, &1, Map.get(by_key, &1.application_key)))
           |> Enum.sort_by(& &1.name),
         permissions: permissions(scope, mission_id),
         spacecraft_count: spacecraft_count(scope, mission_id, context)
       }}
    end
  end

  @doc "One app's row after an action."
  @spec app(Scope.t(), binary(), binary(), HostContext.t() | nil) ::
          {:ok, map()} | {:error, :app_not_found}
  def app(%Scope{} = scope, mission_id, key, context \\ nil) do
    with {:ok, %{apps: apps}} <-
           load_at(scope, mission_id, context || HostContext.mission(mission_id)) do
      case Enum.find(apps, &(&1.key == key)) do
        nil -> {:error, :app_not_found}
        row -> {:ok, row}
      end
    end
  end

  defp spacecraft_count(scope, mission_id, %HostContext{placement: :mission}),
    do: SpacecraftStore.count_mission_spacecraft(scope.organization_id, mission_id)

  defp spacecraft_count(_scope, _mission_id, %HostContext{}), do: 1

  @spec permissions(Scope.t(), binary()) :: [binary()]
  def permissions(scope, mission_id) do
    params = %{organization_id: scope.organization_id, mission_id: mission_id}
    if Policy.authorize(scope, :operate_mission, params) == :ok, do: ["apps.install"], else: []
  end

  defp row(scope, context, %ApplicationDefinition{} = definition, installation) do
    definition
    |> row(installation)
    |> Map.put(:status, AppStatus.status(scope, definition, installation, context))
  end

  defp row(%ApplicationDefinition{} = definition, installation) do
    state = if is_nil(installation), do: :not_installed, else: state(installation.lifecycle_state)
    version = installation_version(installation)

    %{
      key: definition.application_key,
      name: definition.display_name,
      description: definition.description,
      installed: state == :installed,
      state: state,
      version: if(state != :not_installed, do: version),
      available_version: definition.version,
      update_available: update_available?(state, version, definition.version),
      consequence_if_missing: nil
    }
  end

  # Registry versions are positive integers; the shipped definition is newer when it is greater.
  @doc false
  @spec update_available?(atom(), term(), term()) :: boolean()
  def update_available?(state, installed, available)
      when state in [:installed, :disabled] and is_integer(installed) and is_integer(available),
      do: available > installed

  def update_available?(_state, _installed, _available), do: false

  defp state(:disabled), do: :disabled
  defp state(:uninstalled), do: :not_installed
  defp state(_active), do: :installed

  defp installation_version(nil), do: nil
  defp installation_version(installation), do: installation.application_version
end
