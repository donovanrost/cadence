defmodule CadenceWeb.MissionPage do
  @moduledoc "Host composition and action boundary for core mission pages."

  alias Cadence.Missions.Creation
  alias Cadence.Reads.Missions.Pages

  @routes %{
    "/missions" => "mission_list",
    "/missions/new" => "mission_new",
    "/missions/:mission_id" => "mission_overview"
  }

  def load(scope, %{route: route, params: params}) do
    case Map.fetch(@routes, route) do
      {:ok, page} -> snapshot(scope, page, params["mission_id"])
      :error -> nil
    end
  end

  def creation_session(previous, scope, %{route: "/missions/new"}, path) do
    case previous do
      %{path: ^path, organization_id: organization_id}
      when organization_id == scope.organization_id ->
        previous

      _ ->
        %{path: path, organization_id: scope.organization_id, token: Ecto.UUID.generate()}
    end
  end

  def creation_session(_previous, _scope, _info, _path), do: nil

  def matches?(socket, token) when is_binary(token) do
    case socket.assigns[:mission_creation_session] do
      %{token: ^token, path: path, organization_id: organization_id} ->
        path == socket.assigns.host_path and
          organization_id == socket.assigns.current_scope.organization_id

      _ ->
        false
    end
  end

  def matches?(_socket, _token), do: false

  def presentation(assigns) do
    case {assigns[:mission_page], assigns[:mission_creation_session]} do
      {page, %{token: token}} when is_map(page) -> Map.put(page, :creation_token, token)
      {page, _} -> page
    end
  end

  def action(_scope, "validate", input), do: result(Creation.validate(input))
  def action(scope, "save", input), do: result(Creation.create(scope, input))

  defp result({:ok, data}), do: %{status: "ok", data: data, errors: %{}}

  defp result({:error, errors}) when is_map(errors) and not is_struct(errors),
    do: %{status: "invalid", errors: errors}

  defp result({:error, _reason}),
    do: %{
      status: "unavailable",
      errors: %{},
      message: "The mission could not be created. Try again."
    }

  defp snapshot(scope, page, mission_id) do
    case Pages.load(scope, page, mission_id) do
      {:ok, data} -> %{version: 1, page: page, status: "ready", data: data}
      {:error, _reason} -> %{version: 1, page: page, status: "unavailable"}
    end
  rescue
    _exception -> %{version: 1, page: page, status: "unavailable"}
  end
end
