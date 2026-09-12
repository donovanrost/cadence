defmodule CadenceWeb.SpacecraftPage do
  @moduledoc "Host composition for core spacecraft browsing and scoped identity forms."

  alias Cadence.Reads.Spacecraft.Pages
  alias Cadence.Spacecraft.{Identity, ProfileCreation}

  @identity_routes [
    "/missions/:mission_id/spacecraft/profiles/new",
    "/missions/:mission_id/spacecraft/new",
    "/missions/:mission_id/spacecraft/:spacecraft_id/edit",
    "/missions/:mission_id/spacecraft/:spacecraft_id/identity"
  ]

  @routes %{
    "/missions/:mission_id/spacecraft/:spacecraft_id" => {"spacecraft_show", ["spacecraft_id"]},
    "/missions/:mission_id/spacecraft/:spacecraft_id/readiness" =>
      {"spacecraft_readiness", ["spacecraft_id"]},
    "/missions/:mission_id/spacecraft/profiles/new" => {"profile_new", []},
    "/missions/:mission_id/spacecraft/new" => {"spacecraft_new", []},
    "/missions/:mission_id/spacecraft/:spacecraft_id/edit" =>
      {"spacecraft_edit", ["spacecraft_id"]},
    "/missions/:mission_id/spacecraft/:spacecraft_id/identity" =>
      {"spacecraft_edit", ["spacecraft_id"]},
    "/missions/:mission_id/spacecraft" =>
      {"spacecraft_list", ~w(q sort dir page pageSize filter)},
    "/missions/:mission_id/spacecraft/profiles" => {"profile_list", []},
    "/missions/:mission_id/spacecraft/profiles/:profile_id" => {"profile_show", ["profile_id"]}
  }

  def load(scope, %{route: route, params: params}) do
    case Map.fetch(@routes, route) do
      {:ok, {page, keys}} -> snapshot(scope, page, params["mission_id"], Map.take(params, keys))
      :error -> nil
    end
  end

  def identity_session(previous, scope, %{route: route, params: params}, path)
      when route in @identity_routes do
    case previous do
      %{path: ^path, organization_id: organization_id}
      when organization_id == scope.organization_id ->
        previous

      _ ->
        %{
          path: path,
          organization_id: scope.organization_id,
          mission_id: params["mission_id"],
          spacecraft_id: params["spacecraft_id"],
          page: elem(Map.fetch!(@routes, route), 0),
          token: Ecto.UUID.generate()
        }
    end
  end

  def identity_session(_previous, _scope, _info, _path), do: nil

  def matches?(socket, token) when is_binary(token) do
    case socket.assigns[:spacecraft_identity_session] do
      %{token: ^token, path: path, organization_id: organization_id} ->
        path == socket.assigns.host_path and
          organization_id == socket.assigns.current_scope.organization_id

      _ ->
        false
    end
  end

  def matches?(_socket, _token), do: false

  def presentation(assigns) do
    case {assigns[:spacecraft_page], assigns[:spacecraft_identity_session]} do
      {page, %{token: token}} when is_map(page) -> Map.put(page, :form_token, token)
      {page, _} -> page
    end
  end

  def action(scope, session, event, input) do
    case execute(scope, session, event, input) do
      {:ok, data} ->
        %{status: "ok", data: data, errors: %{}}

      {:error, errors} when is_map(errors) and not is_struct(errors) ->
        %{status: "invalid", errors: errors}

      {:error, _reason} ->
        %{status: "unavailable", errors: %{}}
    end
  rescue
    _exception -> %{status: "unavailable", errors: %{}}
  end

  defp execute(scope, %{page: "profile_new"} = session, event, input),
    do: ProfileCreation.action(scope, session.mission_id, event, input)

  defp execute(scope, session, event, input),
    do: Identity.action(scope, session.mission_id, session.spacecraft_id, event, input)

  defp snapshot(scope, page, mission_id, params) do
    case Pages.load(scope, page, mission_id, params) do
      {:ok, data} -> %{version: 1, page: page, status: "ready", data: data}
      {:error, _reason} -> %{version: 1, page: page, status: "unavailable"}
    end
  end
end
