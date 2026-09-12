defmodule Cadence.Dashboards.SettingsAuthoring do
  @moduledoc "Dashboard-bound, observed-revision settings and sharing effects."
  alias Cadence.Dashboards.{
    Authoring,
    AuthoringInput,
    Document,
    Documents,
    Management,
    SettingsInput,
    SettingsStore
  }

  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Repo

  def execute(scope, mission, dashboard, event, input) do
    with :ok <- Authoring.authorize(scope, mission),
         true <- AuthoringInput.id?(dashboard),
         {:ok, command} <- SettingsInput.admit(event, input),
         {:ok, _} <- Documents.fetch(scope.organization_id, mission, dashboard) do
      normalize(run(scope, mission, dashboard, event, command))
    else
      false -> {:error, :invalid_input}
      error -> normalize(error)
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end

  # Document persistence owns its commit and subsequent runtime invalidation.
  # Sharing effects instead hold the dashboard lock through their insert/update.
  defp run(scope, mission, dashboard, event, command)
       when event in ["save_settings", "archive_dashboard"] do
    row = SettingsStore.dashboard(scope.organization_id, mission, dashboard)

    with :ok <- observed(row, command),
         {:ok, resource} <- effect(scope, row, event, command),
         do: {:ok, receipt(row, event, resource)}
  end

  defp run(scope, mission, dashboard, event, command) do
    SettingsStore.with_dashboard(scope.organization_id, mission, dashboard, :write, fn row ->
      with :ok <- observed(row, command),
           {:ok, resource} <- effect(scope, row, event, command) do
        receipt(row, event, resource)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp observed(%{lifecycle_state: "active"} = row, command) do
    if row.latest_version == command["expected_version"] and
         row.lock_version == command["expected_revision"],
       do: :ok,
       else: {:error, :conflict}
  end

  defp observed(_, _), do: {:error, :unavailable}

  defp effect(scope, row, "save_settings", fields) do
    document = DashboardRow.to_document(row)
    metadata = document.metadata |> Map.delete(:tags) |> Map.put("tags", fields["tags"])

    next = %{
      document
      | name: String.trim(fields["name"]),
        description: String.trim(fields["description"]),
        defaults: fields["defaults"],
        metadata: metadata
    }

    Documents.update(scope.organization_id, row.mission_id, row.dashboard_id, next,
      expected_version: row.latest_version,
      expected_revision: row.lock_version,
      created_by: scope.user.user_id,
      change_summary: "Updated dashboard settings"
    )
  end

  defp effect(scope, row, "archive_dashboard", _) do
    case Documents.archive(scope.organization_id, row.mission_id, row.dashboard_id,
           expected_version: row.latest_version,
           expected_revision: row.lock_version,
           actor_id: scope.user.user_id
         ) do
      :ok -> {:ok, nil}
      error -> error
    end
  end

  defp effect(scope, row, "create_share", fields),
    do:
      Management.create_share(scope.organization_id, row.mission_id, row.dashboard_id, %{},
        created_by: scope.user.user_id,
        data_visibility: fields["data_visibility"],
        expires_in_hours: fields["expires_in_hours"]
      )

  defp effect(scope, row, "create_snapshot", fields),
    do:
      Management.create_snapshot(
        scope.organization_id,
        row.mission_id,
        DashboardRow.to_document(row),
        %{},
        created_by: scope.user.user_id,
        data_visibility: fields["data_visibility"]
      )

  defp effect(scope, row, "revoke_share", fields),
    do:
      SettingsStore.revoke_share(
        scope.organization_id,
        row.mission_id,
        row.dashboard_id,
        fields["share_id"]
      )

  defp receipt(row, event, resource) do
    changed? = event in ["save_settings", "archive_dashboard"]

    %{
      version: 1,
      dashboard_id: row.dashboard_id,
      event: event,
      document_version:
        if(event == "save_settings", do: Document.version(resource), else: row.latest_version),
      revision: row.lock_version + if(changed?, do: 1, else: 0),
      resource_id: resource_id(event, resource)
    }
  end

  defp resource_id(event, share) when event in ["create_share", "revoke_share"],
    do: share.dashboard_share_id

  defp resource_id("create_snapshot", snapshot), do: snapshot.dashboard_snapshot_id
  defp resource_id(_, _), do: nil
  defp normalize({:ok, receipt}), do: {:ok, receipt}
  defp normalize({:error, %Ecto.Changeset{}}), do: {:error, :invalid_input}
  defp normalize({:error, {:invalid_dashboard_document, _}}), do: {:error, :invalid_input}
  defp normalize({:error, {:dashboard_version_conflict, _}}), do: {:error, :conflict}
  defp normalize({:error, :dashboard_revision_conflict}), do: {:error, :conflict}
  defp normalize({:error, :dashboard_not_found}), do: {:error, :unavailable}

  defp normalize({:error, code})
       when code in [:forbidden, :invalid_input, :conflict, :unavailable], do: {:error, code}

  defp normalize(_), do: {:error, :unknown}
end
