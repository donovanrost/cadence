defmodule CadenceWeb.HostPageLive do
  @moduledoc "Authenticated context and event transport for the persistent Vue host."
  use CadenceWeb, :live_view

  alias CadenceWeb.SettingsPage
  alias CadenceWeb.SpacecraftConfigurationPage

  alias Cadence.Catalog.Reimport
  alias Cadence.Reads.OperationalContext

  alias CadenceWeb.{
    ActivationApprovals,
    CatalogPage,
    HostContext,
    HostPageAuthorization,
    OpsLandingPage,
    OpsTimelinePage,
    SpacecraftPage
  }

  alias Plug.Conn.{InvalidQueryError, Query}

  @impl true
  def mount(_params, session, socket) do
    session =
      Map.take(session, ["user_session_token", "current_organization_id", "admin_mode_expires_at"])

    {:ok, Phoenix.LiveView.put_private(socket, :host_navigation_session, session)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    location = URI.parse(uri)
    path = location.path <> if(location.query, do: "?" <> location.query, else: "")

    case prepare_context(socket, path) do
      {:ok, socket} -> {:noreply, socket}
      {:halt, socket} -> {:noreply, socket}
      :error -> {:noreply, redirect(socket, to: "/")}
    end
  end

  @impl true
  def handle_event("host:ops-page:read", %{"path" => path, "id" => id} = params, socket)
      when id in ["data-operations.history", "data-operations.history-manage"] do
    with true <- CadenceWeb.OpsHistoricalWorkflowsPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsHistoricalWorkflowsPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsHistoricalWorkflowsPage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => id, "event" => event, "input" => input} = params,
        socket
      )
      when id in ["data-operations.history", "data-operations.history-manage"] do
    with true <- CadenceWeb.OpsHistoricalWorkflowsPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsHistoricalWorkflowsPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsHistoricalWorkflowsPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("host:context", %{"path" => path}, socket) do
    case prepare_context(socket, path) do
      {:ok, socket} -> {:reply, %{ok: true, snapshot: snapshot(socket.assigns)}, socket}
      {:halt, socket} -> {:noreply, socket}
      :error -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => id} = params,
        socket
      )
      when id in [
             "planning.contact-schedule",
             "planning.contact-record",
             "planning.reservation-review"
           ] do
    with true <- CadenceWeb.OpsContactSchedulingPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsContactSchedulingPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsContactSchedulingPage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{
          "path" => path,
          "id" => id,
          "event" => event,
          "input" => input
        } =
          params,
        socket
      )
      when id in [
             "planning.contact-schedule",
             "planning.contact-record",
             "planning.reservation-review"
           ] do
    with true <- CadenceWeb.OpsContactSchedulingPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsContactSchedulingPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsContactSchedulingPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => id} = params,
        socket
      )
      when id in ["commanding.stages", "commanding.stage-create", "commanding.stage-workbench"] do
    with true <- CadenceWeb.OpsCommandStagesPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandStagesPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsCommandStagesPage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "commanding.workspace"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsCommandWorkspacePage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandWorkspacePage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsCommandWorkspacePage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => "commanding.workspace", "event" => event, "input" => input} =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsCommandWorkspacePage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandWorkspacePage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsCommandWorkspacePage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{
          "path" => path,
          "id" => id,
          "event" => event,
          "input" => input
        } =
          params,
        socket
      )
      when id in ["commanding.stages", "commanding.stage-create", "commanding.stage-workbench"] do
    with true <- CadenceWeb.OpsCommandStagesPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandStagesPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsCommandStagesPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "commanding.authoring"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsCommandAuthoringPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandAuthoringPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsCommandAuthoringPage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{
          "path" => path,
          "id" => "commanding.authoring",
          "event" => event,
          "input" => input
        } =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsCommandAuthoringPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandAuthoringPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsCommandAuthoringPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "commanding.queue-submission"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsCommandQueuePage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandQueuePage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsCommandQueuePage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{
          "path" => path,
          "id" => "commanding.queue-submission",
          "event" => event,
          "input" => input
        } =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsCommandQueuePage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandQueuePage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsCommandQueuePage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "commanding.review"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsCommandReviewPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandReviewPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsCommandReviewPage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{
          "path" => path,
          "id" => "commanding.review",
          "event" => event,
          "input" => input
        } =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsCommandReviewPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCommandReviewPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsCommandReviewPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "planning.plan-review"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsPlanReviewPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsPlanReviewPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsPlanReviewPage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{
          "path" => path,
          "id" => "planning.plan-review",
          "event" => event,
          "input" => input
        } =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsPlanReviewPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsPlanReviewPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsPlanReviewPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => id} = params,
        socket
      )
      when id in ["planning.fleet-start", "planning.fleet-run"] do
    with true <- CadenceWeb.OpsFleetWorkflowPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsFleetWorkflowPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsFleetWorkflowPage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => id, "event" => event, "input" => input} = params,
        socket
      )
      when id in ["planning.fleet-start", "planning.fleet-run"] do
    with true <- CadenceWeb.OpsFleetWorkflowPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsFleetWorkflowPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsFleetWorkflowPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "limits.alarm-conditions"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsAlarmConditionsPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsAlarmConditionsPage.matches?(socket, params) do
      {:reply, %{ok: true, snapshot: CadenceWeb.OpsAlarmConditionsPage.read(socket)}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "planning.fleet-directory"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsFleetDirectoryPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsFleetDirectoryPage.matches?(socket, params) do
      {:reply, %{ok: true, snapshot: CadenceWeb.OpsFleetDirectoryPage.read(socket)}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("host:catalog", %{"path" => path, "event" => "reimport"}, socket) do
    with true <- path == socket.assigns.host_path,
         {:ok, %{route: "/missions/:mission_id/catalog/artifacts/:artifact_id", params: params}} <-
           resolve_path(path),
         {:ok, socket} <- prepare_context(socket, path),
         {:ok, result} <-
           Reimport.execute(
             socket.assigns.current_scope,
             params["mission_id"],
             params["artifact_id"]
           ) do
      {:reply, %{ok: true, snapshot: %{href: result["href"]}}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _invalid -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:spacecraft",
        %{"path" => path, "event" => event, "input" => input, "token" => token},
        socket
      )
      when event in ["validate", "save"] do
    with true <- path == socket.assigns.host_path,
         true <- SpacecraftPage.matches?(socket, token),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- SpacecraftPage.matches?(socket, token) do
      result =
        SpacecraftPage.action(
          socket.assigns.current_scope,
          socket.assigns.spacecraft_identity_session,
          event,
          input
        )

      socket =
        if event == "save" and result.status == "ok",
          do: assign(socket, :spacecraft_identity_session, nil),
          else: socket

      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _invalid -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:activation",
        %{"path" => path, "token" => token, "input" => input},
        socket
      ) do
    with true <- path == socket.assigns.host_path,
         true <- ActivationApprovals.matches?(socket, token),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- ActivationApprovals.matches?(socket, token) do
      result =
        ActivationApprovals.decide(
          socket.assigns.current_scope,
          socket.assigns.activation_review_session,
          input
        )

      socket =
        if result.status == "ok",
          do: assign(socket, :activation_review_session, nil),
          else: socket

      case prepare_context(socket, path) do
        {:ok, socket} ->
          {:reply, %{ok: true, snapshot: %{result: result, page: snapshot(socket.assigns)}},
           socket}

        {:halt, socket} ->
          {:noreply, socket}

        _ ->
          {:reply, %{ok: false}, socket}
      end
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:spacecraft-configuration",
        %{"path" => path, "event" => event, "input" => input},
        socket
      )
      when event in ["save", "review", "activate", "decide", "catalog"] do
    with true <- path == socket.assigns.host_path,
         {:ok, info} <- resolve_path(path),
         true <- SpacecraftConfigurationPage.route?(info.route),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params) do
      result =
        SpacecraftConfigurationPage.action(
          socket.assigns.current_scope,
          info.params,
          event,
          input
        )

      case prepare_context(socket, path) do
        {:ok, socket} ->
          {:reply, %{ok: true, snapshot: Map.put(result, :host, snapshot(socket.assigns))},
           socket}

        {:halt, socket} ->
          {:noreply, socket}

        :error ->
          {:reply, %{ok: false}, socket}
      end
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:reply, %{ok: false}, socket}

  @impl true
  def handle_info({:settings_changed, org, mission}, socket) do
    if SettingsPage.relevant?(socket, org, mission) do
      case prepare_context(socket, socket.assigns.host_path) do
        {:ok, socket} -> {:noreply, socket}
        {:halt, socket} -> {:noreply, socket}
        :error -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:spacecraft_configuration_changed, org, mission}, socket) do
    if socket.assigns[:spacecraft_configuration_subscription] == {org, mission} do
      case prepare_context(socket, socket.assigns.host_path) do
        {:ok, socket} -> {:noreply, socket}
        {:halt, socket} -> {:noreply, socket}
        :error -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:commanding_changed, org, mission}, socket),
    do: {:noreply, CadenceWeb.OpsCommandWorkspacePage.changed(socket, org, mission)}

  def handle_info({:command_workspace_flush, token}, socket),
    do: {:noreply, CadenceWeb.OpsCommandWorkspacePage.flush(socket, token)}

  def handle_info({:command_workspace_reconcile, token}, socket),
    do: {:noreply, CadenceWeb.OpsCommandWorkspacePage.reconcile(socket, token)}

  # L21: the notifications page is gone (DECISIONS #79); these broadcasts refresh nothing here.
  def handle_info({event, _record}, socket)
      when event in [:notification_created, :notification_updated, :invitation_accepted],
      do: {:noreply, socket}

  defp prepare_context(socket, path) do
    with {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params) do
      socket = assign(socket, host_path: path, page_title: "Cadence")
      socket = SettingsPage.prepare(socket, info, path)

      socket =
        assign(socket,
          activation_approvals: ActivationApprovals.load(socket.assigns.current_scope, info),
          activation_review_session:
            ActivationApprovals.session(
              socket.assigns[:activation_review_session],
              socket.assigns.current_scope,
              info,
              path
            ),
          ops_landing_page: OpsLandingPage.load(socket.assigns.current_scope, info),
          timeline_page: OpsTimelinePage.load(socket.assigns.current_scope, info),
          spacecraft_page: SpacecraftPage.load(socket.assigns.current_scope, info),
          spacecraft_identity_session:
            SpacecraftPage.identity_session(
              socket.assigns[:spacecraft_identity_session],
              socket.assigns.current_scope,
              info,
              path
            ),
          catalog: CatalogPage.load(socket.assigns.current_scope, info)
        )
        |> SpacecraftConfigurationPage.subscribe(info)
        |> CadenceWeb.OpsExplorationPage.prepare(info, path)
        |> CadenceWeb.OpsCommandPage.prepare(info, path)
        |> CadenceWeb.OpsCommandHistoryPage.prepare(info, path)
        |> CadenceWeb.OpsCommandReviewPage.prepare(info, path)
        |> CadenceWeb.OpsCommandQueuePage.prepare(info, path)
        |> CadenceWeb.OpsCommandAuthoringPage.prepare(info, path)
        |> CadenceWeb.OpsCommandStagesPage.prepare(info, path)
        |> CadenceWeb.OpsCommandWorkspacePage.prepare(info, path)
        |> CadenceWeb.OpsAlarmConditionsPage.prepare(info, path)
        |> CadenceWeb.OpsFleetDirectoryPage.prepare(info, path)
        |> CadenceWeb.OpsFleetWorkflowPage.prepare(info, path)
        |> CadenceWeb.OpsPlanReviewPage.prepare(info, path)
        |> CadenceWeb.OpsContactSchedulingPage.prepare(info, path)
        |> CadenceWeb.OpsHistoricalWorkflowsPage.prepare(info, path)

      socket =
        if socket.assigns[:ops_context_active?] do
          socket
          |> assign(:active_dashboard_id, info.params["dashboard_id"])
          |> assign(
            :ops_context,
            OperationalContext.pin_command_focus(
              socket.assigns.ops_context,
              info.params["focus_command_id"]
            )
          )
        else
          socket
        end

      {:ok, socket}
    else
      {:halt, socket} -> {:halt, socket}
      _invalid -> :error
    end
  end

  defp resolve_path(path) when is_binary(path) and byte_size(path) <= 8192 do
    with %URI{scheme: nil, host: nil, fragment: nil, path: "/" <> _} = uri <- URI.parse(path),
         %{phoenix_live_view: {__MODULE__, _, _, _}, host_policy: _} = info <-
           Phoenix.Router.route_info(CadenceWeb.Router, "GET", uri.path, "localhost") do
      # Resource identity comes from the matched path, never query parameters.
      params = Map.merge(Query.decode(uri.query || ""), info.path_params)
      {:ok, Map.put(info, :params, params)}
    else
      _invalid -> :error
    end
  rescue
    ArgumentError -> :error
    InvalidQueryError -> :error
  end

  defp resolve_path(_path), do: :error

  defp snapshot(assigns) do
    %{
      path: assigns.host_path,
      context:
        assigns
        |> HostContext.from_assigns()
        |> Map.drop([:nav_context, :nav_item, :ops_nav_item, :active_dashboard_id]),
      activation_approvals: ActivationApprovals.presentation(assigns),
      catalog: assigns[:catalog],
      timeline_page: assigns[:timeline_page],
      ops_landing_page: assigns[:ops_landing_page],
      spacecraft_page: SpacecraftPage.presentation(assigns),
      ops_page: assigns[:ops_page]
    }
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, snapshot: snapshot(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue id="application-shell" v-component="BrowserHost" snapshot={@snapshot} v-ssr={false} />
    </Layouts.app>
    """
  end
end
