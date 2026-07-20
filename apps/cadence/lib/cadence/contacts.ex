defmodule Cadence.Contacts do
  @moduledoc """
  Persistence and lifecycle boundary for scheduled and realized contacts.
  """

  alias Cadence.Contacts.{
    ContactAction,
    ContactLifecycle,
    ContactRuntimeConfig,
    ContactStore,
    LinkAssignment,
    LinkAssignmentStore,
    LinkSetup,
    PathTemplate,
    PathTemplateStore,
    ProfileStore,
    ProviderProfile,
    RealizedContact,
    ScheduledContact,
    SchedulerReadModel,
    TransportProfile
  }

  alias Cadence.Missions

  @spec persist_provider_profile(binary(), ProviderProfile.t()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def persist_provider_profile(organization_id, %ProviderProfile{} = provider_profile)
      when is_binary(organization_id) do
    ProfileStore.persist_provider_profile(organization_id, provider_profile)
  end

  @spec create_shared_link(binary(), binary(), map()) ::
          {:ok,
           %{
             provider: ProviderProfile.t(),
             transport: TransportProfile.t() | nil,
             path_templates: [PathTemplate.t()]
           }}
          | {:error, term()}
  def create_shared_link(organization_id, mission_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(attrs) do
    LinkSetup.create_shared_link(organization_id, mission_id, attrs)
  end

  @spec apply_link_template(binary(), binary(), PathTemplate.t(), [map()], map()) ::
          {:ok,
           %{
             rows: [map()],
             applied_count: non_neg_integer(),
             skipped_count: non_neg_integer(),
             failed_count: non_neg_integer()
           }}
  def apply_link_template(
        organization_id,
        mission_id,
        %PathTemplate{} = source_template,
        spacecraft,
        attrs
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_list(spacecraft) and
             is_map(attrs) do
    LinkSetup.apply_link_template(organization_id, mission_id, source_template, spacecraft, attrs)
  end

  @spec persist_link_assignment(binary(), LinkAssignment.t()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def persist_link_assignment(organization_id, %LinkAssignment{} = assignment)
      when is_binary(organization_id) do
    LinkAssignmentStore.persist(organization_id, assignment)
  end

  @spec fetch_link_assignment(binary(), binary(), binary()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def fetch_link_assignment(organization_id, mission_id, link_assignment_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(link_assignment_id) do
    LinkAssignmentStore.fetch(organization_id, mission_id, link_assignment_id)
  end

  @spec fetch_link_assignment(binary(), binary()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def fetch_link_assignment(mission_id, link_assignment_id)
      when is_binary(mission_id) and is_binary(link_assignment_id) do
    LinkAssignmentStore.fetch(mission_id, link_assignment_id)
  end

  @spec list_link_assignments(binary(), binary()) :: [LinkAssignment.t()]
  def list_link_assignments(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    LinkAssignmentStore.list(organization_id, mission_id)
  end

  @spec delete_link_assignment(binary(), binary(), binary(), map()) ::
          {:ok, LinkAssignment.t()} | {:error, term()}
  def delete_link_assignment(
        organization_id,
        mission_id,
        link_assignment_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(link_assignment_id) and is_map(metadata_patch) do
    LinkAssignmentStore.delete(
      organization_id,
      mission_id,
      link_assignment_id,
      metadata_patch
    )
  end

  @spec persist_provider_profile(ProviderProfile.t()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def persist_provider_profile(%ProviderProfile{} = provider_profile) do
    ProfileStore.persist_provider_profile(provider_profile)
  end

  @spec fetch_provider_profile(binary(), binary()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile(mission_id, provider_profile_id)
      when is_binary(mission_id) and is_binary(provider_profile_id) do
    ProfileStore.fetch_provider_profile(mission_id, provider_profile_id)
  end

  @spec fetch_provider_profile(binary(), binary(), binary()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile(organization_id, mission_id, provider_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) do
    ProfileStore.fetch_provider_profile(organization_id, mission_id, provider_profile_id)
  end

  @spec fetch_provider_profile_version(binary(), binary(), pos_integer()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile_version(mission_id, provider_profile_id, version)
      when is_binary(mission_id) and is_binary(provider_profile_id) and is_integer(version) and
             version > 0 do
    ProfileStore.fetch_provider_profile_version(mission_id, provider_profile_id, version)
  end

  @spec fetch_provider_profile_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def fetch_provider_profile_version(organization_id, mission_id, provider_profile_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_integer(version) and version > 0 do
    ProfileStore.fetch_provider_profile_version(
      organization_id,
      mission_id,
      provider_profile_id,
      version
    )
  end

  @spec list_provider_profiles(binary()) :: [ProviderProfile.t()]
  def list_provider_profiles(mission_id) when is_binary(mission_id) do
    ProfileStore.list_provider_profiles(mission_id)
  end

  @spec list_provider_profiles(binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ProfileStore.list_provider_profiles(organization_id, mission_id)
  end

  @spec list_provider_profile_versions(binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profile_versions(mission_id, provider_profile_id)
      when is_binary(mission_id) and is_binary(provider_profile_id) do
    ProfileStore.list_provider_profile_versions(mission_id, provider_profile_id)
  end

  @spec list_provider_profile_versions(binary(), binary(), binary()) :: [ProviderProfile.t()]
  def list_provider_profile_versions(organization_id, mission_id, provider_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) do
    ProfileStore.list_provider_profile_versions(organization_id, mission_id, provider_profile_id)
  end

  @spec version_provider_profile(binary(), binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def version_provider_profile(organization_id, mission_id, provider_profile_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_map(attrs) do
    ProfileStore.version_provider_profile(organization_id, mission_id, provider_profile_id, attrs)
  end

  @spec delete_provider_profile(binary(), binary(), binary(), map()) ::
          {:ok, ProviderProfile.t()} | {:error, term()}
  def delete_provider_profile(
        organization_id,
        mission_id,
        provider_profile_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_profile_id) and is_map(metadata_patch) do
    ProfileStore.delete_provider_profile(
      organization_id,
      mission_id,
      provider_profile_id,
      metadata_patch
    )
  end

  @spec persist_transport_profile(binary(), TransportProfile.t()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def persist_transport_profile(organization_id, %TransportProfile{} = transport_profile)
      when is_binary(organization_id) do
    ProfileStore.persist_transport_profile(organization_id, transport_profile)
  end

  @spec persist_transport_profile(TransportProfile.t()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def persist_transport_profile(%TransportProfile{} = transport_profile) do
    ProfileStore.persist_transport_profile(transport_profile)
  end

  @spec fetch_transport_profile(binary(), binary()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile(mission_id, transport_profile_id)
      when is_binary(mission_id) and is_binary(transport_profile_id) do
    ProfileStore.fetch_transport_profile(mission_id, transport_profile_id)
  end

  @spec fetch_transport_profile(binary(), binary(), binary()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile(organization_id, mission_id, transport_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) do
    ProfileStore.fetch_transport_profile(organization_id, mission_id, transport_profile_id)
  end

  @spec fetch_transport_profile_version(binary(), binary(), pos_integer()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile_version(mission_id, transport_profile_id, version)
      when is_binary(mission_id) and is_binary(transport_profile_id) and is_integer(version) and
             version > 0 do
    ProfileStore.fetch_transport_profile_version(mission_id, transport_profile_id, version)
  end

  @spec fetch_transport_profile_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def fetch_transport_profile_version(organization_id, mission_id, transport_profile_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_integer(version) and version > 0 do
    ProfileStore.fetch_transport_profile_version(
      organization_id,
      mission_id,
      transport_profile_id,
      version
    )
  end

  @spec list_transport_profiles(binary()) :: [TransportProfile.t()]
  def list_transport_profiles(mission_id) when is_binary(mission_id) do
    ProfileStore.list_transport_profiles(mission_id)
  end

  @spec list_transport_profiles(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profiles(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ProfileStore.list_transport_profiles(organization_id, mission_id)
  end

  @spec list_transport_profile_versions(binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profile_versions(mission_id, transport_profile_id)
      when is_binary(mission_id) and is_binary(transport_profile_id) do
    ProfileStore.list_transport_profile_versions(mission_id, transport_profile_id)
  end

  @spec list_transport_profile_versions(binary(), binary(), binary()) :: [TransportProfile.t()]
  def list_transport_profile_versions(organization_id, mission_id, transport_profile_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) do
    ProfileStore.list_transport_profile_versions(
      organization_id,
      mission_id,
      transport_profile_id
    )
  end

  @spec version_transport_profile(binary(), binary(), binary(), map()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def version_transport_profile(organization_id, mission_id, transport_profile_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_map(attrs) do
    ProfileStore.version_transport_profile(
      organization_id,
      mission_id,
      transport_profile_id,
      attrs
    )
  end

  @spec delete_transport_profile(binary(), binary(), binary(), map()) ::
          {:ok, TransportProfile.t()} | {:error, term()}
  def delete_transport_profile(
        organization_id,
        mission_id,
        transport_profile_id,
        metadata_patch \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(transport_profile_id) and is_map(metadata_patch) do
    ProfileStore.delete_transport_profile(
      organization_id,
      mission_id,
      transport_profile_id,
      metadata_patch
    )
  end

  @spec persist_path_template(binary(), PathTemplate.t()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def persist_path_template(organization_id, %PathTemplate{} = path_template)
      when is_binary(organization_id) do
    PathTemplateStore.persist(organization_id, path_template)
  end

  @spec persist_path_template(PathTemplate.t()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def persist_path_template(%PathTemplate{} = path_template) do
    PathTemplateStore.persist(path_template)
  end

  @spec fetch_path_template(binary(), binary()) :: {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template(mission_id, path_template_id)
      when is_binary(mission_id) and is_binary(path_template_id) do
    PathTemplateStore.fetch(mission_id, path_template_id)
  end

  @spec fetch_path_template(binary(), binary(), binary()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template(organization_id, mission_id, path_template_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) do
    PathTemplateStore.fetch(organization_id, mission_id, path_template_id)
  end

  @spec fetch_path_template_version(binary(), binary(), pos_integer()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template_version(mission_id, path_template_id, version)
      when is_binary(mission_id) and is_binary(path_template_id) and is_integer(version) and
             version > 0 do
    PathTemplateStore.fetch_version(mission_id, path_template_id, version)
  end

  @spec fetch_path_template_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def fetch_path_template_version(organization_id, mission_id, path_template_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_integer(version) and version > 0 do
    PathTemplateStore.fetch_version(organization_id, mission_id, path_template_id, version)
  end

  @spec list_path_templates(binary()) :: [PathTemplate.t()]
  def list_path_templates(mission_id) when is_binary(mission_id) do
    PathTemplateStore.list(mission_id)
  end

  @spec list_path_templates(binary(), binary()) :: [PathTemplate.t()]
  def list_path_templates(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    PathTemplateStore.list(organization_id, mission_id)
  end

  @spec list_path_template_versions(binary(), binary()) :: [PathTemplate.t()]
  def list_path_template_versions(mission_id, path_template_id)
      when is_binary(mission_id) and is_binary(path_template_id) do
    PathTemplateStore.list_versions(mission_id, path_template_id)
  end

  @spec list_path_template_versions(binary(), binary(), binary()) :: [PathTemplate.t()]
  def list_path_template_versions(organization_id, mission_id, path_template_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(path_template_id) do
    PathTemplateStore.list_versions(organization_id, mission_id, path_template_id)
  end

  @spec version_path_template(binary(), binary(), binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def version_path_template(organization_id, mission_id, path_template_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_map(attrs) do
    PathTemplateStore.version(organization_id, mission_id, path_template_id, attrs)
  end

  @spec delete_path_template(binary(), binary(), binary(), map()) ::
          {:ok, PathTemplate.t()} | {:error, term()}
  def delete_path_template(organization_id, mission_id, path_template_id, metadata_patch \\ %{})
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(path_template_id) and is_map(metadata_patch) do
    PathTemplateStore.delete(organization_id, mission_id, path_template_id, metadata_patch)
  end

  @spec persist_scheduled_contact(ScheduledContact.t()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def persist_scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    with {:ok, prepared_scheduled_contact} <- ContactRuntimeConfig.prepare(scheduled_contact),
         :ok <- ContactRuntimeConfig.validate(prepared_scheduled_contact) do
      ContactStore.persist_scheduled(prepared_scheduled_contact)
    end
  end

  @spec persist_scheduled_contact(binary(), ScheduledContact.t()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def persist_scheduled_contact(organization_id, %ScheduledContact{} = scheduled_contact)
      when is_binary(organization_id) do
    with {:ok, scoped_scheduled_contact} <-
           put_organization_scope(scheduled_contact, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_scheduled_contact.organization_id,
             scoped_scheduled_contact.mission_id
           ) do
      persist_scheduled_contact(scoped_scheduled_contact)
    end
  end

  @spec fetch_scheduled_contact(binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled_contact(mission_id, scheduled_contact_id)
      when is_binary(mission_id) and is_binary(scheduled_contact_id) do
    ContactStore.fetch_scheduled(mission_id, scheduled_contact_id)
  end

  @spec fetch_scheduled_contact(binary(), binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) do
    ContactStore.fetch_scheduled(organization_id, mission_id, scheduled_contact_id)
  end

  @spec fetch_scheduled_contact_by_provider_ref(binary(), binary()) ::
          {:ok, ScheduledContact.t()} | {:error, :scheduled_contact_not_found}
  def fetch_scheduled_contact_by_provider_ref(mission_id, provider_contact_ref)
      when is_binary(mission_id) and is_binary(provider_contact_ref) do
    ContactStore.fetch_scheduled_by_provider_ref(mission_id, provider_contact_ref)
  end

  @spec list_scheduled_contacts(binary()) :: [ScheduledContact.t()]
  def list_scheduled_contacts(mission_id) when is_binary(mission_id) do
    ContactStore.list_scheduled(mission_id)
  end

  @spec list_scheduled_contacts(binary(), binary()) :: [ScheduledContact.t()]
  def list_scheduled_contacts(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactStore.list_scheduled(organization_id, mission_id)
  end

  @spec list_contact_actions(binary(), keyword()) :: [ContactAction.t()]
  def list_contact_actions(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    ContactStore.list_actions(mission_id, opts)
  end

  @spec list_contact_actions(binary(), binary(), keyword()) :: [ContactAction.t()]
  def list_contact_actions(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    ContactStore.list_actions(organization_id, mission_id, opts)
  end

  @spec persist_realized_contact(RealizedContact.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def persist_realized_contact(%RealizedContact{} = realized_contact) do
    ContactStore.persist_realized(realized_contact)
  end

  @spec persist_realized_contact(binary(), RealizedContact.t()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def persist_realized_contact(organization_id, %RealizedContact{} = realized_contact)
      when is_binary(organization_id) do
    with {:ok, scoped_realized_contact} <-
           put_organization_scope(realized_contact, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_realized_contact.organization_id,
             scoped_realized_contact.mission_id
           ) do
      persist_realized_contact(scoped_realized_contact)
    end
  end

  @spec fetch_realized_contact(binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    ContactStore.fetch_realized(mission_id, realized_contact_id)
  end

  @spec fetch_realized_contact(binary(), binary(), binary()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def fetch_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    ContactStore.fetch_realized(organization_id, mission_id, realized_contact_id)
  end

  @spec list_realized_contacts(binary()) :: [RealizedContact.t()]
  def list_realized_contacts(mission_id) when is_binary(mission_id) do
    ContactStore.list_realized(mission_id)
  end

  @spec list_realized_contacts(binary(), binary()) :: [RealizedContact.t()]
  def list_realized_contacts(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ContactStore.list_realized(organization_id, mission_id)
  end

  @spec reconcile(DateTime.t()) :: {:ok, map()}
  def reconcile(%DateTime{} = reference_time) do
    ContactLifecycle.reconcile(reference_time)
  end

  @spec reconcile(binary(), DateTime.t()) :: {:ok, map()}
  def reconcile(mission_id, %DateTime{} = reference_time) when is_binary(mission_id) do
    ContactLifecycle.reconcile(mission_id, reference_time)
  end

  @spec next_contact_scheduler_wakeup(binary(), DateTime.t()) :: DateTime.t() | nil
  def next_contact_scheduler_wakeup(mission_id, %DateTime{} = reference_time)
      when is_binary(mission_id) do
    reference_time
    |> list_contact_scheduler_wakeups(mission_id)
    |> SchedulerReadModel.next_wakeup(mission_id)
  end

  @spec list_contact_scheduler_wakeups(DateTime.t()) :: [
          %{mission_id: binary(), wake_at: DateTime.t()}
        ]
  def list_contact_scheduler_wakeups(reference_time, mission_id \\ nil)

  def list_contact_scheduler_wakeups(%DateTime{} = reference_time, mission_id)
      when is_nil(mission_id) or is_binary(mission_id) do
    ContactStore.scheduler_wakeups(reference_time, mission_id)
  end

  @spec contact_scheduler_projection(binary()) :: %{
          scheduled_contacts: %{optional(binary()) => ScheduledContact.t()}
        }
  def contact_scheduler_projection(mission_id) when is_binary(mission_id) do
    ContactStore.scheduler_projection(mission_id)
  end

  @spec realize_scheduled_contact(binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def realize_scheduled_contact(mission_id, scheduled_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(scheduled_contact_id) and is_list(opts) do
    ContactLifecycle.realize_scheduled(mission_id, scheduled_contact_id, opts)
  end

  @spec realize_scheduled_contact(binary(), binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def realize_scheduled_contact(organization_id, mission_id, scheduled_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) and is_list(opts) do
    ContactLifecycle.realize_scheduled(
      organization_id,
      mission_id,
      scheduled_contact_id,
      opts
    )
  end

  @spec cancel_scheduled_contact(binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel_scheduled_contact(mission_id, scheduled_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(scheduled_contact_id) and is_list(opts) do
    ContactLifecycle.cancel_scheduled(mission_id, scheduled_contact_id, opts)
  end

  @spec cancel_scheduled_contact(binary(), binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel_scheduled_contact(organization_id, mission_id, scheduled_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) and is_list(opts) do
    ContactLifecycle.cancel_scheduled(
      organization_id,
      mission_id,
      scheduled_contact_id,
      opts
    )
  end

  @spec start_realized_contact(RealizedContact.t()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(%RealizedContact{} = realized_contact) do
    ContactLifecycle.start_realized(realized_contact)
  end

  @spec start_realized_contact(binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    ContactLifecycle.start_realized(mission_id, realized_contact_id)
  end

  @spec start_realized_contact(binary(), binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    ContactLifecycle.start_realized(organization_id, mission_id, realized_contact_id)
  end

  @spec end_realized_contact_early(binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def end_realized_contact_early(mission_id, realized_contact_id, opts \\ [])
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_list(opts) do
    ContactLifecycle.end_realized_early(mission_id, realized_contact_id, opts)
  end

  @spec end_realized_contact_early(binary(), binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def end_realized_contact_early(organization_id, mission_id, realized_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_list(opts) do
    ContactLifecycle.end_realized_early(
      organization_id,
      mission_id,
      realized_contact_id,
      opts
    )
  end

  @spec stop_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    ContactLifecycle.stop_realized(mission_id, realized_contact_id)
  end

  @spec stop_realized_contact(binary(), binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    ContactLifecycle.stop_realized(organization_id, mission_id, realized_contact_id)
  end

  defp put_organization_scope(%ScheduledContact{} = scheduled_contact, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case scheduled_contact.organization_id do
      nil ->
        {:ok, %ScheduledContact{scheduled_contact | organization_id: organization_id}}

      ^organization_id ->
        {:ok, scheduled_contact}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          scheduled_contact.mission_id}}
    end
  end

  defp put_organization_scope(%RealizedContact{} = realized_contact, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case realized_contact.organization_id do
      nil ->
        {:ok, %RealizedContact{realized_contact | organization_id: organization_id}}

      ^organization_id ->
        {:ok, realized_contact}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          realized_contact.mission_id}}
    end
  end
end
