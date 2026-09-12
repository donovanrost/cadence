defmodule CadenceWeb.OpsPlaylistPage do
  @moduledoc "Host placement and page-instance admission for playlist authoring and presentation."
  alias Cadence.Dashboards.PlaylistAuthoring
  alias Cadence.Reads.Dashboards.Playlists
  alias Phoenix.Component
  @directory "/missions/:mission_id/ops/dashboards/playlists"
  @present "/missions/:mission_id/ops/dashboards/playlists/:playlist_id/present"

  def prepare(socket, %{route: route, params: params}, path)
      when route in [@directory, @present] do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, path}

    session =
      case socket.assigns[:ops_playlist_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            sequence: 0,
            phase: "ready",
            model: nil,
            query: Map.drop(params, ~w(mission_id playlist_id)),
            playlist: params["playlist_id"]
          }
      end

    model =
      case read(scope, session) do
        {:ok, model} -> model
        _ -> nil
      end

    put_session(socket, %{session | model: model})
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_playlist_session, nil)

  def matches?(socket, %{"id" => "dashboards.playlists", "path" => path, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_playlist_session] do
      %{identity: {org, user, mission, ^path}, token: ^token, playlist: nil} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def action(socket, "search_dashboards", input) do
    {_, _, mission, _} = socket.assigns.ops_playlist_session.identity

    result =
      case Playlists.search(socket.assigns.current_scope, mission, input) do
        {:ok, data} -> %{status: "ok", data: data}
        _ -> %{status: "unavailable"}
      end

    {result, socket}
  end

  def action(socket, event, input) do
    session = socket.assigns.ops_playlist_session

    case admit(session, event, input) do
      {:ok, fields} ->
        session = %{session | sequence: input["sequence"], phase: "review"}
        {status, receipt, session} = effect(socket.assigns.current_scope, session, event, fields)
        {reply(status, receipt, session), put_session(socket, session)}

      _ ->
        {reply("rejected", nil, session), socket}
    end
  end

  defp admit(session, event, %{"sequence" => sequence, "fields" => fields} = input)
       when map_size(input) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
              is_map(fields) do
    if sequence == session.sequence + 1, do: admit_fields(session, event, fields), else: :error
  end

  defp admit(_, _, _), do: :error

  defp admit_fields(_, "reload_playlists", fields) when fields == %{}, do: {:ok, fields}

  defp admit_fields(%{phase: "ready", model: model}, "create_playlist", fields)
       when is_map(model),
       do: {:ok, fields}

  defp admit_fields(_, _, _), do: :error

  defp effect(scope, session, "reload_playlists", _) do
    case read(scope, session) do
      {:ok, model} -> {"ok", nil, %{session | model: model, phase: "ready"}}
      _ -> {"unknown", nil, session}
    end
  end

  defp effect(scope, session, "create_playlist", fields) do
    {_, _, mission, _} = session.identity

    case PlaylistAuthoring.create(scope, mission, fields) do
      {:ok, receipt} ->
        {"ok", receipt, session}

      {:error, code} when code in [:invalid_input, :invalid_dashboard] ->
        {"invalid", nil, %{session | phase: "ready"}}

      _ ->
        {"unknown", nil, session}
    end
  end

  defp read(scope, session) do
    {_, _, mission, _} = session.identity

    if session.playlist,
      do: Playlists.present(scope, mission, session.playlist, session.query),
      else: Playlists.directory(scope, mission, session.query)
  end

  defp reply(status, receipt, session),
    do: %{
      status: status,
      receipt: receipt,
      sequence: session.sequence,
      phase: session.phase,
      model: session.model
    }

  defp put_session(socket, session) do
    {org, _, mission, _} = session.identity
    context = %{organizationId: org, missionId: mission}

    context =
      if session.playlist, do: Map.put(context, :resourceId, session.playlist), else: context

    data =
      if session.playlist, do: session.model, else: Map.take(session, [:model, :sequence, :phase])

    page = %{
      id: if(session.playlist, do: "dashboards.playlist-present", else: "dashboards.playlists"),
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: context,
      status: if(session.model, do: "ready", else: "unavailable")
    }

    page = if session.model, do: Map.put(page, :data, data), else: page
    Component.assign(socket, ops_playlist_session: session, ops_page: page)
  end
end
