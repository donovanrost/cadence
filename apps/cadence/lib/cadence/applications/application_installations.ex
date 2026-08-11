defmodule Cadence.Applications.ApplicationInstallations do
  @moduledoc """
  Host-owned lifecycle boundary for durable application installations.

  The initial implementation supports one installation of an application per
  mission or spacecraft scope. The explicit scope fields and version pin keep
  a profile declaration or application-owned configuration row distinct from
  the installation itself.
  """

  import Ecto.Query

  alias Cadence.Applications.ApplicationInstallation
  alias Cadence.Applications.ApplicationInstallation.LifecycleEvent
  alias Cadence.Applications.ApplicationInstallations.{InstallationRow, LifecycleEventRow}
  alias Cadence.Applications.{ConfigurationReference, HostContext, Registry}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @type fetch_error ::
          :application_not_installed
          | :application_installation_disabled
          | :application_installation_uninstalled
          | :application_installation_scope_required

  @spec install(Scope.t(), HostContext.t(), binary(), keyword()) ::
          {:ok, ApplicationInstallation.t()} | {:error, term()}
  def install(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_key,
        opts \\ []
      )
      when is_binary(application_key) and is_list(opts) do
    requested_version = Keyword.get(opts, :application_version, :latest)

    with {:ok, definition} <- Registry.fetch_available(application_key, requested_version),
         :ok <- ensure_host_scope(definition.installable_scopes, host_context),
         {:ok, scope_attrs} <- scope_attrs(current_scope, host_context),
         :ok <- authorize_management(current_scope, scope_attrs),
         {:ok, actor_id} <- actor_id(current_scope),
         {:ok, _host_resource} <- fetch_host_resource(scope_attrs) do
      transact(fn ->
        persist_install(
          scope_attrs,
          application_key,
          definition.version,
          Keyword.get(opts, :metadata, %{}),
          actor_id
        )
      end)
    end
  end

  @spec disable(Scope.t(), HostContext.t(), binary()) ::
          {:ok, ApplicationInstallation.t()} | {:error, term()}
  def disable(%Scope{} = current_scope, %HostContext{} = host_context, application_key)
      when is_binary(application_key) do
    with {:ok, scope_attrs} <- scope_attrs(current_scope, host_context),
         :ok <- authorize_management(current_scope, scope_attrs),
         {:ok, actor_id} <- actor_id(current_scope) do
      transact(fn -> persist_disable(scope_attrs, application_key, actor_id) end)
    end
  end

  @spec uninstall(Scope.t(), HostContext.t(), binary()) ::
          {:ok, ApplicationInstallation.t()} | {:error, term()}
  def uninstall(%Scope{} = current_scope, %HostContext{} = host_context, application_key)
      when is_binary(application_key) do
    with {:ok, scope_attrs} <- scope_attrs(current_scope, host_context),
         :ok <- authorize_management(current_scope, scope_attrs),
         {:ok, actor_id} <- actor_id(current_scope) do
      transact(fn -> persist_uninstall(scope_attrs, application_key, actor_id) end)
    end
  end

  @spec put_configuration_reference(
          Scope.t(),
          HostContext.t(),
          binary(),
          ConfigurationReference.t()
        ) :: {:ok, ApplicationInstallation.t()} | {:error, term()}
  def put_configuration_reference(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        application_key,
        %ConfigurationReference{} = configuration_ref
      )
      when is_binary(application_key) do
    with {:ok, scope_attrs} <- scope_attrs(current_scope, host_context),
         :ok <- authorize_management(current_scope, scope_attrs),
         {:ok, actor_id} <- actor_id(current_scope) do
      transact(fn ->
        persist_configuration_reference(
          scope_attrs,
          application_key,
          configuration_ref,
          actor_id
        )
      end)
    end
  end

  @spec fetch(Scope.t(), HostContext.t(), binary()) ::
          {:ok, ApplicationInstallation.t()} | {:error, fetch_error()}
  def fetch(%Scope{} = current_scope, %HostContext{} = host_context, application_key)
      when is_binary(application_key) do
    with {:ok, scope_attrs} <- scope_attrs(current_scope, host_context),
         :ok <- authorize_management(current_scope, scope_attrs) do
      case scoped_row(scope_attrs, application_key) do
        nil -> {:error, :application_not_installed}
        row -> {:ok, InstallationRow.to_domain(row)}
      end
    end
  end

  @spec fetch_installed(Scope.t(), HostContext.t(), binary()) ::
          {:ok, ApplicationInstallation.t()} | {:error, fetch_error()}
  def fetch_installed(%Scope{} = current_scope, %HostContext{} = host_context, application_key)
      when is_binary(application_key) do
    with {:ok, %ApplicationInstallation{} = installation} <-
           fetch(current_scope, host_context, application_key),
         :installed <- installation.lifecycle_state do
      {:ok, installation}
    else
      :disabled -> {:error, :application_installation_disabled}
      :uninstalled -> {:error, :application_installation_uninstalled}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list(Scope.t(), HostContext.t()) ::
          {:ok, [ApplicationInstallation.t()]} | {:error, fetch_error()}
  def list(%Scope{} = current_scope, %HostContext{} = host_context) do
    with {:ok, scope_attrs} <- scope_attrs(current_scope, host_context),
         :ok <- authorize_management(current_scope, scope_attrs) do
      installations =
        InstallationRow
        |> where(
          [row],
          row.organization_id == ^scope_attrs.organization_id and
            row.mission_id == ^scope_attrs.mission_id and
            row.scope_kind == ^Atom.to_string(scope_attrs.scope_kind) and
            row.scope_id == ^scope_attrs.scope_id
        )
        |> order_by([row], asc: row.application_key)
        |> Repo.all()
        |> Enum.map(&InstallationRow.to_domain/1)

      {:ok, installations}
    end
  end

  @spec list_for_mission(Scope.t(), binary(), keyword()) ::
          {:ok, [ApplicationInstallation.t()]} | {:error, term()}
  def list_for_mission(%Scope{} = current_scope, mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    scope_attrs = %{
      organization_id: current_scope.organization_id,
      mission_id: mission_id
    }

    with true <- is_binary(scope_attrs.organization_id),
         true <- scope_matches_mission?(current_scope.mission_id, mission_id),
         :ok <- authorize_management(current_scope, scope_attrs),
         {:ok, _mission} <- Missions.fetch_mission(scope_attrs.organization_id, mission_id) do
      installations =
        InstallationRow
        |> where(
          [row],
          row.organization_id == ^scope_attrs.organization_id and row.mission_id == ^mission_id
        )
        |> maybe_filter_lifecycle_state(Keyword.get(opts, :lifecycle_state))
        |> order_by(
          [row],
          asc: row.scope_kind,
          asc: row.scope_id,
          asc: row.application_key
        )
        |> Repo.all()
        |> Enum.map(&InstallationRow.to_domain/1)

      {:ok, installations}
    else
      false -> {:error, :application_installation_scope_required}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_events(Scope.t(), HostContext.t(), binary()) ::
          {:ok, [LifecycleEvent.t()]} | {:error, fetch_error()}
  def list_events(%Scope{} = current_scope, %HostContext{} = host_context, application_key)
      when is_binary(application_key) do
    with {:ok, %ApplicationInstallation{} = installation} <-
           fetch(current_scope, host_context, application_key) do
      events =
        LifecycleEventRow
        |> where(
          [row],
          row.application_installation_id == ^installation.application_installation_id
        )
        |> order_by([row], asc: row.occurred_at, asc: row.inserted_at)
        |> Repo.all()
        |> Enum.map(&LifecycleEventRow.to_domain/1)

      {:ok, events}
    end
  end

  defp persist_install(scope_attrs, application_key, application_version, metadata, actor_id) do
    case locked_row(scope_attrs, application_key) do
      nil ->
        installation =
          ApplicationInstallation.new(%{
            organization_id: scope_attrs.organization_id,
            mission_id: scope_attrs.mission_id,
            scope_kind: scope_attrs.scope_kind,
            scope_id: scope_attrs.scope_id,
            application_key: application_key,
            application_version: application_version,
            lifecycle_state: :installed,
            metadata: metadata
          })

        persist_transition(nil, installation, :installed, actor_id)

      %InstallationRow{} = row ->
        current = InstallationRow.to_domain(row)
        reinstall(row, current, application_version, actor_id)
    end
  end

  defp persist_disable(scope_attrs, application_key, actor_id) do
    case locked_row(scope_attrs, application_key) do
      nil ->
        Repo.rollback(:application_not_installed)

      %InstallationRow{} = row ->
        %ApplicationInstallation{} = current = InstallationRow.to_domain(row)

        case current.lifecycle_state do
          :disabled ->
            current

          :uninstalled ->
            Repo.rollback(:application_installation_uninstalled)

          :installed ->
            updated = %ApplicationInstallation{current | lifecycle_state: :disabled}
            persist_transition(row, updated, :disabled, actor_id)
        end
    end
  end

  defp persist_uninstall(scope_attrs, application_key, actor_id) do
    case locked_row(scope_attrs, application_key) do
      nil ->
        Repo.rollback(:application_not_installed)

      %InstallationRow{} = row ->
        %ApplicationInstallation{} = current = InstallationRow.to_domain(row)

        if current.lifecycle_state == :uninstalled do
          current
        else
          updated = %ApplicationInstallation{current | lifecycle_state: :uninstalled}
          persist_transition(row, updated, :uninstalled, actor_id)
        end
    end
  end

  defp persist_configuration_reference(
         scope_attrs,
         application_key,
         configuration_ref,
         actor_id
       ) do
    case locked_row(scope_attrs, application_key) do
      nil ->
        Repo.rollback(:application_not_installed)

      %InstallationRow{} = row ->
        %ApplicationInstallation{} = current = InstallationRow.to_domain(row)
        update_configuration_reference(row, current, configuration_ref, actor_id)
    end
  end

  defp update_configuration_reference(
         %InstallationRow{} = row,
         %ApplicationInstallation{} = current,
         %ConfigurationReference{} = configuration_ref,
         actor_id
       ) do
    cond do
      current.lifecycle_state == :disabled ->
        Repo.rollback(:application_installation_disabled)

      current.lifecycle_state == :uninstalled ->
        Repo.rollback(:application_installation_uninstalled)

      current.configuration_ref == configuration_ref ->
        current

      true ->
        updated = %ApplicationInstallation{current | configuration_ref: configuration_ref}
        persist_transition(row, updated, :configuration_updated, actor_id)
    end
  end

  defp reinstall(
         %InstallationRow{} = row,
         %ApplicationInstallation{} = current,
         application_version,
         actor_id
       ) do
    updated = %ApplicationInstallation{
      current
      | application_version: application_version,
        lifecycle_state: :installed
    }

    cond do
      current.application_version != application_version ->
        persist_transition(row, updated, :application_upgraded, actor_id)

      current.lifecycle_state == :disabled ->
        persist_transition(row, updated, :enabled, actor_id)

      current.lifecycle_state == :uninstalled ->
        persist_transition(row, updated, :reinstalled, actor_id)

      true ->
        current
    end
  end

  defp persist_transition(row, installation, event_type, actor_id) do
    previous = row && InstallationRow.to_domain(row)

    with {:ok, persisted_row} <-
           Repo.insert_or_update(
             InstallationRow.changeset(row || %InstallationRow{}, installation)
           ),
         persisted = InstallationRow.to_domain(persisted_row),
         {:ok, _event} <-
           Repo.insert(
             LifecycleEventRow.changeset(
               lifecycle_event(previous, persisted, event_type, actor_id)
             )
           ) do
      persisted
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lifecycle_event(previous, current, event_type, actor_id) do
    LifecycleEvent.new(%{
      application_installation_id: current.application_installation_id,
      organization_id: current.organization_id,
      mission_id: current.mission_id,
      scope_kind: current.scope_kind,
      scope_id: current.scope_id,
      application_key: current.application_key,
      event_type: event_type,
      previous_lifecycle_state: previous && previous.lifecycle_state,
      current_lifecycle_state: current.lifecycle_state,
      previous_application_version: previous && previous.application_version,
      current_application_version: current.application_version,
      previous_configuration_version: configuration_version(previous),
      current_configuration_version: configuration_version(current),
      actor_id: actor_id,
      occurred_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      payload: %{}
    })
  end

  defp configuration_version(nil), do: nil
  defp configuration_version(%ApplicationInstallation{configuration_ref: nil}), do: nil

  defp configuration_version(%ApplicationInstallation{configuration_ref: configuration_ref}),
    do: configuration_ref.version

  defp locked_row(scope_attrs, application_key) do
    scope_attrs
    |> scoped_row_query(application_key)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp scoped_row(scope_attrs, application_key) do
    scope_attrs
    |> scoped_row_query(application_key)
    |> Repo.one()
  end

  defp scoped_row_query(scope_attrs, application_key) do
    from(row in InstallationRow,
      where:
        row.organization_id == ^scope_attrs.organization_id and
          row.mission_id == ^scope_attrs.mission_id and
          row.scope_kind == ^Atom.to_string(scope_attrs.scope_kind) and
          row.scope_id == ^scope_attrs.scope_id and row.application_key == ^application_key
    )
  end

  defp scope_attrs(
         %Scope{organization_id: organization_id, mission_id: scoped_mission_id},
         %HostContext{placement: :mission, mission_id: mission_id}
       )
       when is_binary(organization_id) and is_binary(mission_id) do
    if scope_matches_mission?(scoped_mission_id, mission_id) do
      {:ok,
       %{
         organization_id: organization_id,
         mission_id: mission_id,
         scope_kind: :mission,
         scope_id: mission_id
       }}
    else
      {:error, :application_installation_scope_required}
    end
  end

  defp scope_attrs(
         %Scope{organization_id: organization_id, mission_id: scoped_mission_id},
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         }
       )
       when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    if scope_matches_mission?(scoped_mission_id, mission_id) do
      {:ok,
       %{
         organization_id: organization_id,
         mission_id: mission_id,
         scope_kind: :spacecraft,
         scope_id: spacecraft_id
       }}
    else
      {:error, :application_installation_scope_required}
    end
  end

  defp scope_attrs(%Scope{}, %HostContext{}),
    do: {:error, :application_installation_scope_required}

  defp ensure_host_scope(scopes, %HostContext{placement: placement}) do
    if placement in scopes, do: :ok, else: {:error, :unsupported_application_host_context}
  end

  defp fetch_host_resource(%{scope_kind: :mission} = scope_attrs) do
    Missions.fetch_mission(scope_attrs.organization_id, scope_attrs.mission_id)
  end

  defp fetch_host_resource(%{scope_kind: :spacecraft} = scope_attrs) do
    SpacecraftStore.fetch_spacecraft(
      scope_attrs.organization_id,
      scope_attrs.mission_id,
      scope_attrs.scope_id
    )
  end

  defp authorize_management(current_scope, scope_attrs) do
    Policy.authorize(current_scope, :operate_mission, %{
      organization_id: scope_attrs.organization_id,
      mission_id: scope_attrs.mission_id
    })
  end

  defp scope_matches_mission?(nil, _mission_id), do: true
  defp scope_matches_mission?(mission_id, mission_id), do: true
  defp scope_matches_mission?(_scoped_mission_id, _mission_id), do: false

  defp maybe_filter_lifecycle_state(query, nil), do: query

  defp maybe_filter_lifecycle_state(query, lifecycle_state) when is_atom(lifecycle_state) do
    where(query, [row], row.lifecycle_state == ^Atom.to_string(lifecycle_state))
  end

  defp actor_id(%Scope{actor_kind: :user, user: %{user_id: user_id}})
       when is_binary(user_id),
       do: {:ok, user_id}

  defp actor_id(%Scope{
         actor_kind: :service,
         service_identity: %{service_identity_id: service_identity_id}
       })
       when is_binary(service_identity_id),
       do: {:ok, service_identity_id}

  defp actor_id(%Scope{}), do: {:error, :authenticated_actor_required}

  defp transact(fun) do
    case Repo.transaction(fun) do
      {:ok, %ApplicationInstallation{} = installation} -> {:ok, installation}
      {:error, reason} -> {:error, reason}
    end
  end
end
