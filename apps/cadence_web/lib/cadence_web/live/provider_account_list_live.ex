defmodule CadenceWeb.ProviderAccountListLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ExtensionCatalog
  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    {:ok, account_pairs} = ProviderAccounts.list(scope)
    accounts = Enum.map(account_pairs, &elem(&1, 0))

    versions =
      Map.new(account_pairs, fn {account, version} -> {account.provider_account_id, version} end)

    credentials =
      Map.new(accounts, fn account ->
        version = Map.fetch!(versions, account.provider_account_id)

        credential =
          case ProviderCredentials.fetch(
                 scope.organization_id,
                 account.provider_account_id,
                 version.credential_ref
               ) do
            {:ok, credential} -> credential
            {:error, _reason} -> nil
          end

        {account.provider_account_id, credential}
      end)

    card_rows =
      Enum.map(accounts, fn account ->
        provider_account_card(
          account,
          Map.fetch!(versions, account.provider_account_id),
          credentials[account.provider_account_id]
        )
      end)

    {:ok,
     socket
     |> assign(:page_title, "Provider Accounts")
     |> assign(:nav_item, :provider_accounts)
     |> assign(:account_count, length(accounts))
     |> assign(:accounts_empty?, accounts == [])
     |> assign(:account_versions, versions)
     |> assign(:account_credentials, credentials)
     |> stream_configure(:provider_accounts,
       dom_id: &"provider-account-#{&1.id}"
     )
     |> stream(:provider_accounts, card_rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="provider-accounts-page" class="space-y-6">
        <.page_header
          title="Provider Accounts"
          subtitle="Organization-owned ground network control planes. Grant access to missions without copying credentials."
          breadcrumbs={[{"Provider Accounts", nil}]}
        >
          <:title_suffix>{@account_count} registered</:title_suffix>
          <:actions>
            <.button id="new-provider-account-link" navigate={~p"/provider-accounts/new"} class="gap-1">
              <.icon name="hero-plus" class="h-4 w-4" /> New Account
            </.button>
          </:actions>
        </.page_header>

        <.empty_state
          :if={@accounts_empty?}
          icon="hero-globe-alt"
          title="No provider accounts"
          description="Register the simulator or a commercial ground network once, then grant it to the missions that need it."
          action_label="Register provider account"
          action_navigate={~p"/provider-accounts/new"}
        />

        <div
          id="provider-accounts"
          phx-update="stream"
          class="grid gap-4 xl:grid-cols-2"
        >
          <div id="provider-accounts-empty" class="hidden only:block"></div>
          <div
            :for={{dom_id, card} <- @streams.provider_accounts}
            id={dom_id}
          >
            <.vue
              id={"#{dom_id}-component"}
              v-component="ProviderAccountCards"
              card={card}
              v-ssr={false}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp provider_account_card(account, version, credential) do
    %{
      id: "provider-account-#{account.provider_account_id}",
      display_name: account.display_name,
      provider_account_id: account.provider_account_id,
      status: account_health_status(account) |> Atom.to_string(),
      status_label: account_health_label(account),
      provider: provider_label(version),
      config: "v#{account.active_version}",
      credential: credential_label(credential),
      events: ingestion_label(version),
      endpoint: endpoint_summary(version),
      href: ~p"/provider-accounts/#{account.provider_account_id}"
    }
  end

  defp account_health_status(%{credential_status: :revoked}), do: :blocked
  defp account_health_status(%{event_ingestion_status: :degraded}), do: :attention
  defp account_health_status(%{last_validated_at: %DateTime{}}), do: :ready
  defp account_health_status(_account), do: :info

  defp account_health_label(%{credential_status: :revoked}), do: "Credential revoked"
  defp account_health_label(%{event_ingestion_status: :degraded}), do: "Degraded"
  defp account_health_label(%{last_validated_at: %DateTime{}}), do: "Validated"
  defp account_health_label(_account), do: "Not validated"

  defp provider_label(version) do
    case ExtensionCatalog.fetch_provider_connector(Atom.to_string(version.provider_type)) do
      {:ok, connector} -> connector.label
      {:error, _reason} -> version.provider_type |> Atom.to_string() |> String.capitalize()
    end
  end

  defp credential_label(nil), do: "Unavailable"

  defp credential_label(credential),
    do:
      "#{credential.status |> Atom.to_string() |> String.capitalize()} · v#{credential.registry_version}"

  defp ingestion_label(version),
    do: version.event_ingestion_mode |> Atom.to_string() |> String.capitalize()

  defp endpoint_summary(version) do
    uri = URI.parse(version.base_url)
    location = version.region_ref || version.environment_ref
    Enum.join(Enum.reject([uri.host, location], &is_nil/1), " · ")
  end
end
