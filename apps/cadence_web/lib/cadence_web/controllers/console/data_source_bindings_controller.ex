defmodule CadenceWeb.Console.DataSourceBindingsController do
  @moduledoc """
  A mission's data-source bindings and a platform-wide binding's blast radius and history
  (DECISIONS #90, ux U53). Contract: docs/apogee/api/setup.md §Data sources.
  """

  use CadenceWeb, :controller

  alias Cadence.Applications.OpsConsole.Actions.PlatformBindings
  alias Cadence.Auth.Scope
  alias Cadence.Management.DataSources
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  @doc "The mission's own bindings first, then the platform ones it falls back to."
  def index(conn, _params) do
    bindings =
      org(conn)
      |> DataSources.list_data_bindings(mission(conn))
      |> PlatformBindings.mission_bindings(mission(conn))

    json(conn, %{data: ConfigJSON.encode(%{bindings: bindings})})
  end

  @doc "Who switching a platform-wide binding would move now. Re-read when the sheet opens."
  # todo(authz): Cedar should decide who may read a platform binding's blast radius (platform
  # admins in admin mode today, the same rule as the switch).
  def blast_radius(conn, %{"binding_id" => binding_id}) do
    with {:ok, binding} <- binding(conn, binding_id),
         :ok <- shared(binding),
         :ok <- admin_mode(conn),
         {:ok, view} <- PlatformBindings.view(binding) do
      json(conn, %{data: ConfigJSON.encode(view)})
    else
      {:error, reason} -> Problem.respond(conn, reason)
    end
  end

  @doc """
  The binding's history, newest first (50). A platform-wide binding's history is the platform
  admins' record: outside admin mode it shows what happened and when, without the admin's name,
  their reason or the platform-wide counts (other tenants' scale).
  """
  # todo(authz): Cedar should decide who may read a platform binding's full history (platform
  # admins in admin mode today; tenants see it redacted).
  def events(conn, %{"binding_id" => binding_id}) do
    case binding(conn, binding_id) do
      {:ok, binding} ->
        events =
          binding.binding_id
          |> PlatformBindings.events()
          |> redact_for(binding, conn)

        json(conn, %{data: ConfigJSON.encode(%{events: events})})

      {:error, reason} ->
        Problem.respond(conn, reason)
    end
  end

  # The mission's own binding or a platform one it can see.
  defp binding(conn, binding_id) do
    case Enum.find(
           DataSources.list_data_bindings(org(conn), mission(conn)),
           &(&1.binding_id == binding_id)
         ) do
      nil -> {:error, :binding_not_found}
      binding -> {:ok, binding}
    end
  end

  defp redact_for(events, binding, conn) do
    if PlatformBindings.shared?(binding) and not Scope.admin_mode?(conn.assigns.current_scope),
      do: Enum.map(events, &redact/1),
      else: events
  end

  defp redact(event),
    do: %{event | actor: nil, reason: nil, affected_missions: nil, live_passes_total: nil}

  defp shared(binding),
    do: if(PlatformBindings.shared?(binding), do: :ok, else: {:error, :binding_not_shared})

  defp admin_mode(conn) do
    if Scope.admin_mode?(conn.assigns.current_scope), do: :ok, else: {:error, :platform_source}
  end

  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
