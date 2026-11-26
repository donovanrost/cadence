defmodule CadenceWeb.Console.ServiceAccess do
  @moduledoc """
  Which console API actions a service identity's bearer token may reach (#753, #747).

  Services are denied by default. An action is reachable only if it is listed here; every other
  action answers 403 `service_not_allowed` before it runs. Person-only acts (decisions and GO,
  approvals, account, sessions, people, admin, approval-policy settings) are never listed: a
  four-eyes decision is a person's.

  The list is checked from the route (`Phoenix.Router.route_info/4`) in the authenticator, so a
  controller can't forget to opt out. `CadenceWeb.Console.ServiceAccessTest` asserts the list.
  """

  @allowed %{
    CadenceWeb.Console.MissionController => [:show]
  }

  @doc "The allowed `{controller, actions}` map."
  @spec allowed() :: %{module() => [atom()]}
  def allowed, do: @allowed

  @doc "`:ok`, or `{:error, action}` naming the refused `Controller.action`."
  @spec check(Plug.Conn.t()) :: :ok | {:error, binary()}
  def check(%Plug.Conn{} = conn) do
    case Phoenix.Router.route_info(CadenceWeb.Router, conn.method, conn.path_info, conn.host) do
      %{plug: controller, plug_opts: action} when is_atom(controller) and is_atom(action) ->
        if action in Map.get(@allowed, controller, []),
          do: :ok,
          else: {:error, name(controller, action)}

      _no_route ->
        {:error, "unknown"}
    end
  end

  defp name(controller, action),
    do: "#{controller |> Module.split() |> List.last()}.#{action}"
end
