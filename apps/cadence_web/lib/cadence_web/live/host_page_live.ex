defmodule CadenceWeb.HostPageLive do
  @moduledoc "Authenticated context and event transport for the persistent Vue host."
  use CadenceWeb, :live_view

  alias Cadence.Catalog.Reimport
  alias Cadence.Reads.OperationalContext

  alias CadenceWeb.{
    ActivationApprovals,
    AdministrationDiagnostics,
    AdministrationPage,
    ApplicationManagement,
    CatalogPage,
    CatalogUpload,
    CommunicationsSetupPage,
    HostContext,
    HostPageAuthorization,
    MissionModulePage,
    MissionPage,
    NotificationsPage,
    OpsLandingPage,
    OpsTimelinePage,
    OrganizationModulePage,
    PlatformAdministrationPage,
    ProviderAccountDetailPage,
    ProviderAccountRegistrationPage,
    SpacecraftModulePage,
    SpacecraftPage
  }

  alias Plug.Conn.{InvalidQueryError, Query}

  @external_resource Path.expand("../../../../../frontend/apps/host/src/routes.json", __DIR__)
  @management_paths @external_resource
                    |> File.read!()
                    |> Jason.decode!()
                    |> Enum.filter(&(&1["kind"] == "application_management"))
                    |> Enum.map(& &1["path"])

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

  def handle_event("host:ops-page:read", %{"path" => path, "id" => id} = params, socket)
      when id in [
             "data-operations.sources",
             "data-operations.source",
             "data-operations.source-registration",
             "data-operations.source-settings"
           ] do
    with true <- CadenceWeb.OpsDataSourcesPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsDataSourcesPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsDataSourcesPage.read(socket)
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
      when id in [
             "data-operations.sources",
             "data-operations.source",
             "data-operations.source-registration",
             "data-operations.source-settings"
           ] do
    with true <- CadenceWeb.OpsDataSourcesPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsDataSourcesPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsDataSourcesPage.action(socket, event, input)
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
      when id in ["planning.requirement-directory", "planning.requirement-review"] do
    with true <- CadenceWeb.OpsRequirementPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsRequirementPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsRequirementPage.read(socket)
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
          "id" => "planning.requirement-review",
          "event" => event,
          "input" => input
        } =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsRequirementPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsRequirementPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsRequirementPage.action(socket, event, input)
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
        %{"path" => path, "id" => "planning.requirement-templates"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsRequirementTemplatePage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsRequirementTemplatePage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsRequirementTemplatePage.read(socket)
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
          "id" => "planning.requirement-templates",
          "event" => event,
          "input" => input
        } =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsRequirementTemplatePage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsRequirementTemplatePage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsRequirementTemplatePage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "planning.requirement-declaration"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsRequirementDeclarationPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsRequirementDeclarationPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsRequirementDeclarationPage.read(socket)
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
          "id" => "planning.requirement-declaration",
          "event" => event,
          "input" => input
        } =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsRequirementDeclarationPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsRequirementDeclarationPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsRequirementDeclarationPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page:read",
        %{"path" => path, "id" => "planning.fleet-policy"} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsFleetPolicyPage.matches_read?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsFleetPolicyPage.matches_read?(socket, params) do
      {page, socket} = CadenceWeb.OpsFleetPolicyPage.read(socket)
      {:reply, %{ok: true, snapshot: page}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => "planning.fleet-policy", "event" => event, "input" => input} =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsFleetPolicyPage.matches_action?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsFleetPolicyPage.matches_action?(socket, params) do
      {result, socket} = CadenceWeb.OpsFleetPolicyPage.action(socket, event, input)
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

  def handle_event(
        "host:ops-page",
        %{
          "path" => path,
          "id" => "dashboards.execution-diagnostics",
          "event" => event,
          "input" => input
        } = params,
        socket
      ) do
    with true <- CadenceWeb.OpsDiagnosticsPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsDiagnosticsPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.OpsDiagnosticsPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => "dashboards.playlists", "event" => event, "input" => input} =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsPlaylistPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsPlaylistPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.OpsPlaylistPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => "dashboards.library", "event" => event, "input" => input} =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsLibraryPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsLibraryPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.OpsLibraryPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => "dashboards.settings", "event" => event, "input" => input} =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsSettingsPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsSettingsPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.OpsSettingsPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => "dashboards.activity", "event" => event, "input" => input} =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsActivityPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsActivityPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.OpsActivityPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "id" => "dashboards.editor", "event" => event, "input" => input} =
          params,
        socket
      ) do
    with true <- CadenceWeb.OpsEditorPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsEditorPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.OpsEditorPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "event" => "create", "input" => input} = params,
        socket
      ) do
    with true <- CadenceWeb.OpsCreationPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsCreationPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.OpsCreationPage.action(socket, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:ops-page",
        %{"path" => path, "event" => event, "input" => input} = params,
        socket
      )
      when event in ["star", "restore"] do
    with true <- CadenceWeb.OpsDirectoryPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.OpsDirectoryPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.OpsDirectoryPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("host:manage", %{"path" => path, "event" => event} = params, socket)
      when event in ["install", "disable", "uninstall"] do
    # Bind every mutation to its explicit resource path and reauthorize it. A stale
    # page can never accidentally mutate whichever mission was visited afterwards.
    with true <- path == socket.assigns.host_path,
         {:ok, %{route: route}} when route in @management_paths <- resolve_path(path),
         {:ok, socket} <- prepare_context(socket, path) do
      {:noreply, socket} = ApplicationManagement.handle_event(event, params, socket)
      {:reply, %{ok: true, snapshot: snapshot(socket.assigns)}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _invalid -> {:reply, %{ok: false}, socket}
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
        "host:mission",
        %{"path" => path, "event" => event, "input" => input, "token" => token},
        socket
      )
      when event in ["validate", "save"] do
    with true <- path == socket.assigns.host_path,
         true <- MissionPage.matches?(socket, token),
         {:ok, %{route: "/missions/new"}} <- resolve_path(path),
         {:ok, socket} <- prepare_context(socket, path),
         true <- MissionPage.matches?(socket, token) do
      result = MissionPage.action(socket.assigns.current_scope, event, input)

      socket =
        if event == "save" and result.status == "ok",
          do: assign(socket, :mission_creation_session, nil),
          else: socket

      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _invalid -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(event, %{"catalog_upload" => %{"path" => path}} = params, socket)
      when event in ["catalog:upload:validate", "catalog:upload:save", "catalog:upload:cancel"] do
    with true <- CatalogUpload.matches?(socket, params),
         {:ok, socket} <- prepare_context(socket, path),
         true <- CatalogUpload.matches?(socket, params) do
      CatalogUpload.handle_event(event, params, socket)
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
        "host:organization-page",
        %{"event" => event, "input" => input, "path" => path} = params,
        socket
      )
      when event in ["validate", "save"] do
    with true <- ProviderAccountRegistrationPage.matches?(socket, params),
         {:ok, %{route: "/provider-accounts/new"} = info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- ProviderAccountRegistrationPage.matches?(socket, params) do
      {result, socket} = ProviderAccountRegistrationPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:organization-page",
        %{"event" => event, "input" => input, "path" => path} = params,
        socket
      )
      when event in ~w(refresh validate-account rotate-credential revoke-credential grant-mission revoke-grant) do
    with true <- ProviderAccountDetailPage.matches?(socket, params),
         {:ok, %{route: "/provider-accounts/:provider_account_id"} = info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- ProviderAccountDetailPage.matches?(socket, params) do
      {result, socket} = ProviderAccountDetailPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:mission-page",
        %{"id" => id, "event" => event, "input" => input, "path" => path} = params,
        socket
      )
      when id in ~w(comms.provider-new comms.provider-show) and
             event in ~w(create-provider validate-provider sync-provider archive-provider refresh) do
    with true <- CadenceWeb.MissionProviderPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CadenceWeb.MissionProviderPage.matches?(socket, params) do
      {result, socket} = CadenceWeb.MissionProviderPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:mission-page",
        %{"event" => event, "input" => input, "path" => path} = params,
        socket
      )
      when event in ["validate", "save"] do
    with true <- CommunicationsSetupPage.matches?(socket, params),
         {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params),
         true <- CommunicationsSetupPage.matches?(socket, params) do
      {result, socket} = CommunicationsSetupPage.action(socket, event, input)
      {:reply, %{ok: true, snapshot: result}, socket}
    else
      {:halt, socket} -> {:noreply, socket}
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "host:notifications",
        %{"path" => path, "event" => event, "input" => input, "token" => token},
        socket
      )
      when event in ["accept_invitation", "mark_notification_read"] do
    with true <- path == socket.assigns.host_path,
         true <- NotificationsPage.matches?(socket, token),
         {:ok, %{route: "/notifications"}} <- resolve_path(path),
         {:ok, socket} <- prepare_context(socket, path),
         true <- NotificationsPage.matches?(socket, token) do
      result = NotificationsPage.action(socket, event, input)

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

  def handle_event(
        "host:platform-administration",
        %{"path" => path, "event" => event, "input" => input, "token" => token},
        socket
      )
      when event in ["create", "issue_service_identity", "invite"] do
    with true <- path == socket.assigns.host_path,
         true <- PlatformAdministrationPage.matches?(socket, token),
         {:ok, info} <- resolve_path(path),
         true <- PlatformAdministrationPage.action_route?(info.route, event),
         {:ok, socket} <- prepare_context(socket, path),
         true <- PlatformAdministrationPage.matches?(socket, token) do
      {result, socket} = PlatformAdministrationPage.action(socket, event, input)

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
  def handle_info(:catalog_upload_drain, socket) do
    case socket.assigns[:catalog_upload_session] do
      %{phase: :waiting, path: path} ->
        case prepare_context(socket, path) do
          {:ok, socket} -> {:noreply, socket}
          {:halt, socket} -> {:noreply, socket}
          :error -> {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(
        {event, record},
        %{assigns: %{current_scope: %{user: %{user_id: user_id}}}} = socket
      )
      when event in [:notification_created, :notification_updated, :invitation_accepted] and
             is_map(record) do
    recipient_id = Map.get(record, :user_id) || Map.get(record, :accepted_by_user_id)

    if recipient_id == user_id and socket.assigns[:notifications_page] != nil do
      case prepare_context(socket, socket.assigns.host_path) do
        {:ok, socket} -> {:noreply, socket}
        {:halt, socket} -> {:noreply, socket}
        :error -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({event, _record}, socket)
      when event in [:notification_created, :notification_updated, :invitation_accepted],
      do: {:noreply, socket}

  defp prepare_context(socket, path) do
    with {:ok, info} <- resolve_path(path),
         {:cont, socket} <- HostPageAuthorization.prepare(socket, info.host_policy, info.params) do
      socket = assign(socket, host_path: path, page_title: "Cadence")

      diagnostics =
        if info.route == "/admin/runtime" do
          AdministrationDiagnostics.load(socket.assigns.current_scope, info.params)
        else
          []
        end

      socket =
        assign(socket,
          diagnostics: diagnostics,
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
          administration_page: AdministrationPage.load(socket.assigns.current_scope, info),
          mission_page: MissionPage.load(socket.assigns.current_scope, info),
          spacecraft_page: SpacecraftPage.load(socket.assigns.current_scope, info),
          spacecraft_module_page: SpacecraftModulePage.load(socket.assigns.current_scope, info),
          mission_module_page: MissionModulePage.load(socket.assigns.current_scope, info),
          organization_module_page:
            OrganizationModulePage.load(socket.assigns.current_scope, info),
          spacecraft_identity_session:
            SpacecraftPage.identity_session(
              socket.assigns[:spacecraft_identity_session],
              socket.assigns.current_scope,
              info,
              path
            ),
          mission_creation_session:
            MissionPage.creation_session(
              socket.assigns[:mission_creation_session],
              socket.assigns.current_scope,
              info,
              path
            ),
          catalog: CatalogPage.load(socket.assigns.current_scope, info)
        )
        |> NotificationsPage.prepare(info, path)
        |> PlatformAdministrationPage.prepare(info, path)
        |> CatalogUpload.prepare(info, path)
        |> ProviderAccountRegistrationPage.prepare(info, path)
        |> ProviderAccountDetailPage.prepare(info, path)
        |> CommunicationsSetupPage.prepare(info, path)
        |> CadenceWeb.MissionProviderPage.prepare(info, path)
        |> CadenceWeb.OpsDirectoryPage.prepare(info, path)
        |> CadenceWeb.OpsCreationPage.prepare(info, path)
        |> CadenceWeb.OpsWorkspacePage.prepare(info, path)
        |> CadenceWeb.OpsEditorPage.prepare(info, path)
        |> CadenceWeb.OpsActivityPage.prepare(info, path)
        |> CadenceWeb.OpsDiagnosticsPage.prepare(info, path)
        |> CadenceWeb.OpsExplorationPage.prepare(info, path)
        |> CadenceWeb.OpsCommandPage.prepare(info, path)
        |> CadenceWeb.OpsCommandHistoryPage.prepare(info, path)
        |> CadenceWeb.OpsCommandReviewPage.prepare(info, path)
        |> CadenceWeb.OpsCommandQueuePage.prepare(info, path)
        |> CadenceWeb.OpsCommandAuthoringPage.prepare(info, path)
        |> CadenceWeb.OpsCommandStagesPage.prepare(info, path)
        |> CadenceWeb.OpsSettingsPage.prepare(info, path)
        |> CadenceWeb.OpsSharedViewPage.prepare(info, path)
        |> CadenceWeb.OpsLibraryPage.prepare(info, path)
        |> CadenceWeb.OpsPlaylistPage.prepare(info, path)
        |> CadenceWeb.OpsAlarmConditionsPage.prepare(info, path)
        |> CadenceWeb.OpsFleetDirectoryPage.prepare(info, path)
        |> CadenceWeb.OpsFleetWorkflowPage.prepare(info, path)
        |> CadenceWeb.OpsFleetPolicyPage.prepare(info, path)
        |> CadenceWeb.OpsRequirementPage.prepare(info, path)
        |> CadenceWeb.OpsRequirementDeclarationPage.prepare(info, path)
        |> CadenceWeb.OpsRequirementTemplatePage.prepare(info, path)
        |> CadenceWeb.OpsPlanReviewPage.prepare(info, path)
        |> CadenceWeb.OpsContactSchedulingPage.prepare(info, path)
        |> CadenceWeb.OpsHistoricalWorkflowsPage.prepare(info, path)
        |> CadenceWeb.OpsDataSourcesPage.prepare(info, path)

      socket =
        if info.route in @management_paths do
          ApplicationManagement.load(socket)
        else
          assign(socket, presentation: nil, management_error: nil, application_host_context: nil)
        end

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
      presentation: assigns[:presentation],
      application_management: ApplicationManagement.snapshot(assigns),
      diagnostics: assigns[:diagnostics] || [],
      activation_approvals: ActivationApprovals.presentation(assigns),
      catalog: CatalogUpload.presentation(assigns),
      notifications_page: assigns[:notifications_page],
      platform_administration_page: assigns[:platform_administration_page],
      timeline_page: assigns[:timeline_page],
      ops_landing_page: assigns[:ops_landing_page],
      administration_page: assigns[:administration_page],
      mission_page: MissionPage.presentation(assigns),
      spacecraft_page: SpacecraftPage.presentation(assigns),
      spacecraft_module_page: assigns[:spacecraft_module_page],
      mission_module_page: assigns[:mission_module_page],
      ops_page: assigns[:ops_page],
      organization_module_page: assigns[:organization_module_page],
      error: assigns[:management_error]
    }
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        snapshot: snapshot(assigns),
        catalog_upload_form: CatalogUpload.form(assigns)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue id="application-shell" v-component="BrowserHost" snapshot={@snapshot} v-ssr={false} />
      <.form
        :if={@catalog_upload_form}
        for={@catalog_upload_form}
        id="catalog-native-upload-form"
        class="hidden"
        data-catalog-path={@catalog_upload_session.path}
        data-catalog-token={@catalog_upload_session.token}
        phx-change="catalog:upload:validate"
        phx-submit="catalog:upload:save"
      >
        <input id={@catalog_upload_form[:path].id} type="hidden" name={@catalog_upload_form[:path].name} value={@catalog_upload_form[:path].value} />
        <input id={@catalog_upload_form[:token].id} type="hidden" name={@catalog_upload_form[:token].name} value={@catalog_upload_form[:token].value} />
        <input id={@catalog_upload_form[:name].id} type="hidden" name={@catalog_upload_form[:name].name} value={@catalog_upload_form[:name].value} />
        <input id={@catalog_upload_form[:revision_label].id} type="hidden" name={@catalog_upload_form[:revision_label].name} value={@catalog_upload_form[:revision_label].value} />
        <input id={@catalog_upload_form[:revision_notes].id} type="hidden" name={@catalog_upload_form[:revision_notes].name} value={@catalog_upload_form[:revision_notes].value} />
        <.live_file_input upload={@uploads.catalog_artifact} />
      </.form>
    </Layouts.app>
    """
  end
end
