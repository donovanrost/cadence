defmodule CadenceWeb.SettingsPage do
  @moduledoc "Authenticated settings placement, page-bound writes, and scoped live updates."
  import Phoenix.Component, only: [assign: 2, assign: 3]
  alias Cadence.Management.Settings
  alias Cadence.Platform.ScopedReadUpdates

  @routes [
    "/settings",
    "/settings/:section_id",
    "/missions/:mission_id/settings",
    "/missions/:mission_id/settings/:section_id"
  ]
  @consumers [
    "/missions/:mission_id/spacecraft/:spacecraft_id",
    "/missions/:mission_id/ops/activations",
    "/missions/:mission_id/ops/commands/workspace"
  ]

  def prepare(socket, info, path) do
    socket = subscribe(socket, info)
    scope = socket.assigns.current_scope

    if info.route in @routes do
      identity = {path, scope.organization_id, scope.user.user_id}
      previous = socket.assigns[:settings_session]

      session =
        if previous && previous.identity == identity,
          do: previous,
          else: %{
            identity: identity,
            token: Ecto.UUID.generate(),
            mission_id: info.params["mission_id"],
            section_id: Map.get(info.params, "section_id", "cadence.governance")
          }

      assign(socket, settings_session: session, settings_page: load(scope, session))
    else
      assign(socket, settings_session: nil, settings_page: nil)
    end
  end

  def matches?(socket, path, token) do
    case socket.assigns[:settings_session] do
      %{identity: {^path, org, user}, token: ^token} ->
        path == socket.assigns.host_path and org == socket.assigns.current_scope.organization_id and
          user == socket.assigns.current_scope.user.user_id

      _ ->
        false
    end
  end

  def relevant?(socket, org, mission) do
    case socket.assigns[:settings_subscription] do
      {^org, current} -> is_nil(mission) or mission == current
      _ -> false
    end
  end

  def action(scope, session, %{"revision_token" => token, "document" => document} = input)
      when map_size(input) == 2 do
    case Settings.save(scope, session.mission_id, session.section_id, token, document) do
      {:ok, revision} -> %{status: "ok", revision_id: revision.revision_id}
      {:error, :settings_write_unconfirmed} -> %{status: "unconfirmed"}
      {:error, reason} -> %{status: "rejected", message: message(reason)}
    end
  end

  def action(_, _, _), do: %{status: "rejected", message: message(:invalid_settings)}

  defp load(scope, session) do
    context = %{organization_id: scope.organization_id, mission_id: session.mission_id}

    case Settings.load(scope, session.mission_id, session.section_id) do
      {:ok, data} ->
        %{version: 1, status: "ready", token: session.token, context: context, data: data}

      {:error, _} ->
        %{version: 1, status: "unavailable", token: session.token, context: context}
    end
  end

  defp subscribe(socket, info) do
    identity =
      if info.route in (@routes ++ @consumers),
        do: {socket.assigns.current_scope.organization_id, info.params["mission_id"]},
        else: nil

    previous = socket.assigns[:settings_subscription]

    if identity != previous do
      Enum.each(topics(previous), fn {org, mission} ->
        ScopedReadUpdates.unsubscribe(:settings_changed, org, mission)
      end)

      subscribe_topics(socket, identity)
    end

    assign(socket, :settings_subscription, identity)
  end

  defp subscribe_topics(socket, identity) do
    if Phoenix.LiveView.connected?(socket) do
      Enum.each(topics(identity), fn {org, mission} ->
        ScopedReadUpdates.subscribe(:settings_changed, org, mission)
      end)
    end
  end

  defp topics(nil), do: []
  defp topics({org, mission}), do: Enum.uniq([{org, nil}, {org, mission}])

  defp message(:settings_changed),
    do: "These settings changed while you were editing. Review the latest values before saving."

  defp message(:settings_enforced_by_organization),
    do: "Your organization requires this setting. Mission overrides are unavailable."

  defp message(:invalid_settings), do: "Choose a supported setting value."
  defp message(_), do: "This setting could not be saved. Check your access and try again."
end
