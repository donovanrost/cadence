defmodule Cadence.Reads.MissionApps do
  @moduledoc """
  A1, the console's Apps list (Setup rail 08): every application that can be
  installed on a mission, with this mission's installation state.

  - `state`: `installed | disabled | not_installed`. Platform applications are
    always on (`platform: true`) and can't be changed.
  - `permissions`: `apps.install` from the check the install, disable and
    uninstall actions enforce (`ApplicationInstallations`: `:operate_mission`;
    DECISIONS #38).
  - `status` (`Cadence.Reads.AppStatus`) and `surfaces` (§11 L9): what the surface host shows.

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

  @spec load(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def load(%Scope{} = scope, mission_id),
    do: load_at(scope, mission_id, HostContext.mission(mission_id))

  @doc """
  The apps at a host context (L19): `HostContext.mission/1`, or `HostContext.spacecraft/2` for
  the apps installable on one spacecraft, with that spacecraft's installations and only the
  surfaces of that scope.
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
           |> Enum.sort_by(&{not &1.platform, &1.name}),
         permissions: permissions(scope, mission_id)
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

  @spec permissions(Scope.t(), binary()) :: [binary()]
  def permissions(scope, mission_id) do
    params = %{organization_id: scope.organization_id, mission_id: mission_id}
    if Policy.authorize(scope, :operate_mission, params) == :ok, do: ["apps.install"], else: []
  end

  @doc """
  An app's surfaces the console can host, by order: `{surface_id, label, order, purpose, area:
  setup | ops, scope}`. `area` is the placement: `application_workspace` is Setup, `ops_*` Ops;
  administration surfaces aren't hosted.
  """
  @spec surfaces(ApplicationDefinition.t()) :: [map()]
  def surfaces(%ApplicationDefinition{surfaces: surfaces}) do
    for surface <- surfaces || [],
        area = area(surface.placement),
        area != nil do
      %{
        surface_id: surface.surface_id,
        label: get_in(surface.navigation || %{}, [:label]),
        order: get_in(surface.navigation || %{}, [:order]),
        purpose: surface.purpose,
        area: area,
        scope: surface.scope
      }
    end
    |> Enum.sort_by(&{&1.order || 1_000_000, &1.surface_id})
  end

  defp area(:application_workspace), do: :setup
  defp area(placement) when placement in [:ops_workspace, :ops_dock], do: :ops
  defp area(_administration), do: nil

  defp row(scope, context, %ApplicationDefinition{} = definition, installation) do
    level = context.placement

    definition
    |> row(installation)
    |> Map.merge(%{
      status: AppStatus.status(scope, definition, installation, context),
      surfaces:
        if(level == :mission,
          do: surfaces(definition),
          else: Enum.filter(surfaces(definition), &(&1.scope == level))
        )
    })
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
