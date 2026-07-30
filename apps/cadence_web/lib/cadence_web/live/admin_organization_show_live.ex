defmodule CadenceWeb.AdminOrganizationShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Auth.ServiceIdentity

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    case Cadence.Organizations.fetch_organization(org_id) do
      {:ok, organization} ->
        members = Cadence.Accounts.list_organization_members(org_id)
        invitations = Cadence.Accounts.list_pending_invitations(org_id)

        {:ok,
         socket
         |> assign(:page_title, organization.display_name)
         |> assign(:nav_item, :admin_organizations)
         |> assign(:organization, organization)
         |> assign(:members, members)
         |> assign(:invitations, invitations)
         |> assign(:service_identities, Cadence.Auth.list_service_identities(org_id))
         |> assign(:issued_service_token, nil)
         |> assign(
           :service_identity_form,
           to_form(%{"service_identity_id" => "", "display_name" => ""},
             as: :service_identity
           )
         )}

      {:error, :organization_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found.")
         |> push_navigate(to: ~p"/admin/organizations")}
    end
  end

  @impl true
  def handle_event("issue-service-identity", %{"service_identity" => params}, socket) do
    case service_identity_attrs(socket.assigns.organization.organization_id, params) do
      {:ok, attrs} ->
        service_identity = ServiceIdentity.new(attrs)

        case Cadence.Auth.issue_service_identity(service_identity) do
          {:ok, %{service_identity: issued_identity, api_token: api_token}} ->
            {:noreply,
             socket
             |> assign(
               :service_identities,
               Cadence.Auth.list_service_identities(socket.assigns.organization.organization_id)
             )
             |> assign(:issued_service_token, %{
               service_identity: issued_identity,
               api_token: api_token
             })
             |> assign(
               :service_identity_form,
               to_form(%{"service_identity_id" => "", "display_name" => ""},
                 as: :service_identity
               )
             )
             |> put_flash(:info, "Service identity created. Copy its token now.")}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, put_flash(socket, :error, "That service identity ID is already in use.")}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, "Cadence could not create the service identity.")}
        end

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:service_identity_form, to_form(params, as: :service_identity))
         |> put_flash(:error, message)}
    end
  end

  def handle_event("dismiss-service-token", _params, socket) do
    {:noreply, assign(socket, :issued_service_token, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title={@organization.display_name}
        subtitle={@organization.slug}
        breadcrumbs={[
          {"Platform Admin", ~p"/admin"},
          {"Organizations", ~p"/admin/organizations"},
          {@organization.display_name, nil}
        ]}
      >
        <:actions>
          <div class="flex items-center gap-2">
            <.form for={%{}} as={:session} action={~p"/session/organization"} method="put">
              <input type="hidden" name="organization_id" value={@organization.organization_id} />
              <.button type="submit" variant={:secondary}>Open organization</.button>
            </.form>
            <.button navigate={~p"/admin/organizations/#{@organization.organization_id}/invite"}>
              Invite User
            </.button>
          </div>
        </:actions>
      </.page_header>

      <.members_section members={@members} />
      <.invitations_section invitations={@invitations} />
      <.service_identities_section
        service_identities={@service_identities}
        form={@service_identity_form}
        issued_service_token={@issued_service_token}
      />
    </div>
    """
  end

  attr :service_identities, :list, required: true
  attr :form, :any, required: true
  attr :issued_service_token, :any, required: true

  defp service_identities_section(assigns) do
    ~H"""
    <div id="admin-service-identities" class="space-y-3">
      <.section_header
        title="Service identities"
        description="Issue organization-scoped credentials for product API clients."
      />

      <.card :if={@issued_service_token} id="issued-service-token">
        <div class="space-y-3">
          <div>
            <p class="font-semibold">Copy this API token now</p>
            <p class="text-sm text-base-content/60">Cadence will not display it again.</p>
          </div>
          <code class="block break-all border border-primary/20 bg-base-300 p-3 text-xs">
            {@issued_service_token.api_token}
          </code>
          <.button
            id="dismiss-issued-service-token"
            type="button"
            variant={:secondary}
            phx-click="dismiss-service-token"
          >
            Done
          </.button>
        </div>
      </.card>

      <.card padding={:none}>
        <.table id="service-identities-table" rows={@service_identities}>
          <:col :let={identity} label="Name">{identity.display_name}</:col>
          <:col :let={identity} label="ID" mono>{identity.service_identity_id}</:col>
          <:col :let={identity} label="Token hint" mono>{identity.token_hint}</:col>
          <:col :let={identity} label="State">{Phoenix.Naming.humanize(identity.lifecycle_state)}</:col>
        </.table>
      </.card>

      <.form
        for={@form}
        id="service-identity-form"
        phx-submit="issue-service-identity"
        class="grid gap-3 md:grid-cols-[1fr_1fr_auto] md:items-end"
      >
        <.input
          field={@form[:display_name]}
          type="text"
          label="Display name"
          required
        />
        <.input
          field={@form[:service_identity_id]}
          type="text"
          label="ID (optional)"
          placeholder="Generated when blank"
        />
        <.button type="submit">Issue credential</.button>
      </.form>
    </div>
    """
  end

  attr :members, :list, required: true

  defp members_section(assigns) do
    ~H"""
    <div>
      <h2 class="text-lg font-bold mb-3">Members</h2>
      <%= if @members == [] do %>
        <.empty_state title="No members yet." description="Invite someone to get started." />
      <% else %>
        <.card padding={:none}>
          <.table id="org-members-table" rows={@members} row_accent={false}>
            <:col :let={member} label="User">
              <p class="font-semibold">{member.user.display_name}</p>
              <p class="text-sm text-base-content/70">{member.user.email}</p>
            </:col>
            <:col :let={member} label="Role">
              <span class="font-mono text-[0.65rem] uppercase tracking-wide bg-base-300 px-2 py-1">
                {Phoenix.Naming.humanize(member.membership.role)}
              </span>
            </:col>
          </.table>
        </.card>
      <% end %>
    </div>
    """
  end

  attr :invitations, :list, required: true

  defp invitations_section(assigns) do
    ~H"""
    <div>
      <h2 class="text-lg font-bold mb-3">Pending Invitations</h2>
      <%= if @invitations == [] do %>
        <.empty_state compact title="No pending invitations." />
      <% else %>
        <div class="space-y-2">
          <.card :for={inv <- @invitations} padding={:none}>
            <div class="flex items-center justify-between p-3">
              <div>
                <p class="font-semibold">{inv.email}</p>
                <p class="text-sm text-base-content/60">
                  Role: {Phoenix.Naming.humanize(inv.membership_role)}
                  <%= if inv.grant_platform_admin do %>
                    &middot; Platform Admin
                  <% end %>
                </p>
              </div>
              <p class="text-xs text-base-content/60">
                Expires {Calendar.strftime(inv.expires_at, "%Y-%m-%d")}
              </p>
            </div>
          </.card>
        </div>
      <% end %>
    </div>
    """
  end

  defp service_identity_attrs(organization_id, params) do
    case normalize_param(params["display_name"]) do
      nil ->
        {:error, "A service identity display name is required."}

      display_name ->
        attrs = %{
          organization_id: organization_id,
          display_name: display_name,
          capabilities: [:organization_admin],
          lifecycle_state: :active,
          metadata: %{}
        }

        attrs =
          case normalize_param(params["service_identity_id"]) do
            nil -> attrs
            service_identity_id -> Map.put(attrs, :service_identity_id, service_identity_id)
          end

        {:ok, attrs}
    end
  end

  defp normalize_param(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_param(_value), do: nil
end
