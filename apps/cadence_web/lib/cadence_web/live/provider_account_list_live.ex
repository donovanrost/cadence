defmodule CadenceWeb.ProviderAccountListLive do
  @moduledoc false

  use CadenceWeb, :live_view

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

    {:ok,
     socket
     |> assign(:page_title, "Provider Accounts")
     |> assign(:nav_item, :provider_accounts)
     |> assign(:account_count, length(accounts))
     |> assign(:accounts_empty?, accounts == [])
     |> assign(:account_versions, versions)
     |> assign(:account_credentials, credentials)
     |> stream_configure(:provider_accounts,
       dom_id: &"provider-account-#{&1.provider_account_id}"
     )
     |> stream(:provider_accounts, accounts)}
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
          <.link
            :for={{dom_id, account} <- @streams.provider_accounts}
            id={dom_id}
            navigate={~p"/provider-accounts/#{account.provider_account_id}"}
            class="group block border border-base-300 bg-base-200 transition-colors hover:border-primary/50"
          >
            <div class="flex items-start justify-between gap-4 border-b border-base-300 px-5 py-4">
              <div class="min-w-0">
                <p class="hud-label">Ground Network Control Plane</p>
                <h2 class="mt-1 truncate text-lg font-semibold group-hover:text-primary">
                  {account.display_name}
                </h2>
                <p class="mt-1 truncate font-mono text-xs text-base-content/50">
                  {account.provider_account_id}
                </p>
              </div>
              <.status_badge
                status={account_health_status(account)}
                label={account_health_label(account)}
              />
            </div>

            <div class="grid grid-cols-2 gap-px bg-base-300 sm:grid-cols-4">
              <.account_metric label="Provider" value={provider_label(version(@account_versions, account))} />
              <.account_metric label="Config" value={"v#{account.active_version}"} />
              <.account_metric
                label="Credential"
                value={credential_label(@account_credentials[account.provider_account_id])}
              />
              <.account_metric
                label="Events"
                value={ingestion_label(version(@account_versions, account))}
              />
            </div>

            <div class="flex items-center justify-between gap-4 px-5 py-3 text-xs text-base-content/60">
              <span class="font-mono">
                {endpoint_summary(version(@account_versions, account))}
              </span>
              <span class="inline-flex items-center gap-1 text-primary">
                Inspect <.icon name="hero-arrow-right" class="h-3.5 w-3.5" />
              </span>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp account_metric(assigns) do
    ~H"""
    <div class="bg-base-200 px-4 py-3">
      <p class="hud-label">{@label}</p>
      <p class="mt-1 truncate font-mono text-sm">{@value}</p>
    </div>
    """
  end

  defp version(versions, account), do: Map.fetch!(versions, account.provider_account_id)

  defp account_health_status(%{credential_status: :revoked}), do: :blocked
  defp account_health_status(%{event_ingestion_status: :degraded}), do: :attention
  defp account_health_status(%{last_validated_at: %DateTime{}}), do: :ready
  defp account_health_status(_account), do: :info

  defp account_health_label(%{credential_status: :revoked}), do: "Credential revoked"
  defp account_health_label(%{event_ingestion_status: :degraded}), do: "Degraded"
  defp account_health_label(%{last_validated_at: %DateTime{}}), do: "Validated"
  defp account_health_label(_account), do: "Not validated"

  defp provider_label(version),
    do: version.provider_type |> Atom.to_string() |> String.capitalize()

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
