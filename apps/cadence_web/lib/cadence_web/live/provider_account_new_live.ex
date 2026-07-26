defmodule CadenceWeb.ProviderAccountNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ExtensionCatalog
  alias Cadence.Extensions.Presentation.ConfigurationDefinition
  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}
  alias Cadence.Ids

  @impl true
  def mount(_params, _session, socket) do
    account_id = Ids.new("provider_account")
    connector = default_connector()

    {:ok,
     socket
     |> assign(:page_title, "New Provider Account")
     |> assign(:nav_item, :provider_accounts)
     |> assign(:selected_backend_type, "external")
     |> assign(:provider_connector, connector)
     |> assign(:provider_connector_options, provider_connector_options())
     |> assign(:form, to_form(default_params(account_id, connector), as: :provider_account))}
  end

  @impl true
  def handle_event("validate", %{"provider_account" => params}, socket) do
    {:noreply,
     socket
     |> assign(:selected_backend_type, params["backend_type"])
     |> assign(:provider_connector, connector_for(params["provider_type"]))
     |> assign(:form, to_form(params, as: :provider_account))}
  end

  @impl true
  def handle_event("save", %{"provider_account" => params}, socket) do
    scope = socket.assigns.current_scope
    opts = provider_account_live_opts()

    with {:ok, credential_attrs} <- credential_attrs(params),
         {:ok, _credential} <-
           ProviderCredentials.create(
             scope,
             params["provider_account_id"],
             credential_attrs,
             opts
           ),
         {:ok, account_attrs} <- account_attrs(params),
         {:ok, account, _version} <- ProviderAccounts.create(scope, account_attrs, opts) do
      {:noreply, push_navigate(socket, to: ~p"/provider-accounts/#{account.provider_account_id}")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="provider-account-new-page" class="max-w-3xl space-y-6">
        <.page_header
          title="Register Provider Account"
          subtitle="Create one organization-owned control-plane identity. Mission access is granted separately."
          breadcrumbs={[{"Provider Accounts", ~p"/provider-accounts"}, {"New", nil}]}
        />

        <.form
          for={@form}
          id="provider-account-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-8"
        >
          <.input field={@form[:provider_account_id]} type="hidden" />
          <.input field={@form[:credential_ref]} type="hidden" />

          <.form_section number="01" title="Network Identity">
            <.input field={@form[:display_name]} type="text" label="Display Name" required />
            <.input
              field={@form[:provider_type]}
              type="select"
              label="Provider Type"
              options={@provider_connector_options}
              required
            />
            <div
              id="provider-connector-summary"
              data-provider-type={@provider_connector.form_value}
              data-provider-client={Atom.to_string(@provider_connector.client_key)}
              class="grid grid-cols-[0.3rem_minmax(0,1fr)_auto] gap-4 border-y border-base-300/70 bg-base-200/45 px-4 py-3"
            >
              <span class="rounded-full bg-info"></span>
              <div>
                <p class="hud-label">Compiled Provider Connector</p>
                <p class="mt-1 font-medium">{@provider_connector.label}</p>
                <p class="mt-1 text-xs text-base-content/60">
                  {@provider_connector.description}
                </p>
              </div>
              <span class="self-start font-mono text-[0.65rem] uppercase tracking-[0.12em] text-base-content/45">
                {@provider_connector.client_key}
              </span>
            </div>
            <div id="provider-account-boundary-note" class="border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70">
              This account owns provider endpoint and credential configuration. Missions receive
              versioned grants and never copy those values.
            </div>
          </.form_section>

          <.extension_configuration
            definition={@provider_connector.configuration}
            form={@form}
            kind="provider_connector"
          />

          <.form_section number="03" title="Credential Registry">
            <.input
              field={@form[:backend_type]}
              type="select"
              label="Secret Backend"
              options={[{"External secret manager", "external"}, {"Local environment", "env"}]}
              required
            />
            <.input
              field={@form[:backend_key]}
              type="text"
              label={if(@selected_backend_type == "env", do: "Environment Variable", else: "Secret Manager Key")}
              placeholder={if(@selected_backend_type == "env", do: "CADENCE_SIMULATOR_TOKEN", else: "providers/simulator/control-plane")}
              required
            />
            <p id="provider-account-credential-note" class="text-xs text-base-content/60">
              Cadence persists only a stable registry reference and backend locator. Secret
              material is never returned to this page.
            </p>
          </.form_section>

          <.form_section number="04" title="Organization Guardrails">
            <.input
              field={@form[:allowed_services]}
              type="text"
              label="Allowed Services"
              placeholder="telemetry, tracking"
            />
            <.input
              field={@form[:allowed_directions]}
              type="text"
              label="Allowed Directions"
              placeholder="downlink, uplink"
            />
            <.input
              field={@form[:allowed_stations]}
              type="text"
              label="Allowed Stations"
              placeholder="station-alpha, station-beta"
            />
            <.input field={@form[:max_quota]} type="number" min="0" label="Maximum Quota" />
          </.form_section>

          <.form_actions submit="Register Account" cancel_navigate={~p"/provider-accounts"} />
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp default_params(account_id, connector) do
    %{
      "provider_account_id" => account_id,
      "credential_ref" => "provider_credential_#{account_id}",
      "provider_type" => connector.form_value,
      "backend_type" => "external",
      "backend_key" => "providers/simulator/control-plane"
    }
    |> Map.merge(connector.account_defaults)
    |> Map.merge(ConfigurationDefinition.default_params(connector.configuration))
  end

  defp credential_attrs(params) do
    with {:ok, credential_ref} <- required(params, "credential_ref", "Credential reference"),
         {:ok, backend_type} <- backend_type(params["backend_type"]),
         {:ok, backend_key} <- required(params, "backend_key", "Secret backend key") do
      {:ok,
       %{
         provider_credential_ref: credential_ref,
         backend_type: backend_type,
         backend_key: backend_key
       }}
    end
  end

  defp account_attrs(params) do
    with {:ok, connector} <- ExtensionCatalog.fetch_provider_connector(params["provider_type"]),
         {:ok, account_id} <- required(params, "provider_account_id", "Provider Account ID"),
         {:ok, display_name} <- required(params, "display_name", "Display name"),
         {:ok, base_url} <- required(params, "base_url", "Provider API base URL"),
         {:ok, environment_ref} <- required(params, "environment_ref", "Environment"),
         {:ok, credential_ref} <- required(params, "credential_ref", "Credential reference"),
         {:ok, quota} <- optional_nonnegative_integer(params["max_quota"]) do
      {:ok,
       %{
         provider_account_id: account_id,
         display_name: display_name,
         provider_type: connector.provider_type,
         client_key: connector.client_key,
         base_url: base_url,
         region_ref: optional_text(params["region_ref"]),
         environment_ref: environment_ref,
         credential_ref: credential_ref,
         event_ingestion_mode: params["event_ingestion_mode"],
         guardrails:
           compact(%{
             "allowed_services" => comma_list(params["allowed_services"]),
             "allowed_directions" => comma_list(params["allowed_directions"]),
             "allowed_stations" => comma_list(params["allowed_stations"]),
             "max_quota" => quota
           })
       }}
    end
  end

  defp backend_type("external"), do: {:ok, :external}
  defp backend_type("env"), do: {:ok, :env}
  defp backend_type(_value), do: {:error, "Select a supported secret backend."}

  defp required(params, key, label) do
    case optional_text(params[key]) do
      nil -> {:error, "#{label} is required."}
      value -> {:ok, value}
    end
  end

  defp optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_text(_value), do: nil

  defp comma_list(value) do
    value
    |> optional_text()
    |> case do
      nil -> []
      text -> text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  defp optional_nonnegative_integer(value) do
    case optional_text(value) do
      nil -> {:ok, nil}
      text -> parse_nonnegative_integer(text)
    end
  end

  defp parse_nonnegative_integer(text) do
    case Integer.parse(text) do
      {value, ""} when value >= 0 -> {:ok, value}
      _other -> {:error, "Maximum quota must be a non-negative whole number."}
    end
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> value in [nil, []] end)

  defp provider_account_live_opts do
    Application.get_env(:cadence_web, :provider_account_live_opts, [])
  end

  defp format_error(%Ecto.Changeset{} = changeset),
    do: CadenceWeb.CommsComponents.format_error(changeset)

  defp format_error(reason), do: "Could not register provider account: #{inspect(reason)}"

  defp connector_for(form_value) do
    case ExtensionCatalog.fetch_provider_connector(form_value) do
      {:ok, connector} -> connector
      {:error, _reason} -> default_connector()
    end
  end

  defp default_connector do
    {:ok, connector} = ExtensionCatalog.fetch_provider_connector("simulator")
    connector
  end

  defp provider_connector_options do
    ExtensionCatalog.provider_connectors()
    |> Enum.map(&{&1.label, &1.form_value})
    |> Enum.sort()
  end
end
