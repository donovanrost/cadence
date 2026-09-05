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

    account_count = length(accounts)
    accounts_empty? = accounts == []

    {:ok,
     socket
     |> assign(:page_title, "Provider Accounts")
     |> assign(:nav_item, :provider_accounts)
     |> assign(:account_count, account_count)
     |> assign(:accounts_empty?, accounts_empty?)
     |> assign(:account_versions, versions)
     |> assign(:account_credentials, credentials)
     |> assign(:presentation, page_presentation(account_count, accounts_empty?))
     |> stream_configure(:provider_accounts,
       dom_id: &"provider-account-#{&1.id}"
     )
     |> stream(:provider_accounts, card_rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="provider-account-list-page-component"
        v-component="ProviderAccountListPage"
        presentation={@presentation}
        provider_accounts={@streams.provider_accounts}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def federated_props(%Cadence.Auth.Scope{} = scope) do
    with {:ok, account_pairs} <- ProviderAccounts.list(scope) do
      accounts = Enum.map(account_pairs, &elem(&1, 0))

      versions =
        Map.new(account_pairs, fn {account, version} ->
          {account.provider_account_id, version}
        end)

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

      rows =
        Enum.map(accounts, fn account ->
          account
          |> provider_account_card(
            Map.fetch!(versions, account.provider_account_id),
            credentials[account.provider_account_id]
          )
          |> Map.put(:__dom_id, "provider-account-#{account.provider_account_id}")
        end)

      {:ok,
       %{
         presentation: page_presentation(length(accounts), accounts == []),
         provider_accounts: rows
       }}
    end
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp page_presentation(account_count, accounts_empty?) do
    new_account_path = ~p"/provider-accounts/new"

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "provider-accounts-page",
            "class" => "space-y-6"
          })
      },
      "header" => header_presentation(account_count, new_account_path),
      "empty_state" => empty_state_presentation(accounts_empty?, new_account_path),
      "stream" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "provider-accounts",
            "phx-update" => "stream",
            "class" => "grid gap-4 xl:grid-cols-2"
          }),
        "empty_marker" => %{
          "attrs" =>
            presentation_attrs(%{
              "id" => "provider-accounts-empty",
              "class" => "hidden only:block"
            })
        }
      }
    }
  end

  defp header_presentation(account_count, new_account_path) do
    %{
      "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-end justify-between gap-4"})
      },
      "content" => %{"attrs" => %{}},
      "breadcrumbs" => %{
        "attrs" =>
          presentation_attrs(%{
            "aria-label" => "Breadcrumb",
            "class" =>
              "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
          }),
        "items" => [
          %{
            "key" => "provider-accounts",
            "separator" => nil,
            "link" => nil,
            "current" => %{
              "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
              "text" => "Provider Accounts"
            }
          }
        ]
      },
      "title" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
          }),
        "text" => "Provider Accounts",
        "suffix" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "ml-3 font-mono text-base text-base-content/60"
            }),
          "text" => "#{account_count} registered"
        }
      },
      "subtitle" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
          }),
        "text" =>
          "Organization-owned ground network control planes. Grant access to missions without copying credentials."
      },
      "actions" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-center gap-2"}),
        "new_account" => %{
          "attrs" =>
            navigate_attrs(new_account_path, %{
              "id" => "new-provider-account-link",
              "class" => "btn btn-primary btn-sm gap-1"
            }),
          "icon" => %{
            "attrs" => presentation_attrs(%{"class" => "hero-plus h-4 w-4"})
          },
          "text" => "New Account"
        }
      }
    }
  end

  defp empty_state_presentation(true, new_account_path) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" =>
            "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        }),
      "icon" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "hero-globe-alt mx-auto h-10 w-10 text-base-content/30 block"
          })
      },
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "hud-label mt-3"}),
        "text" => "No provider accounts"
      },
      "description" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        "text" =>
          "Register the simulator or a commercial ground network once, then grant it to the missions that need it."
      },
      "action_container" => %{
        "attrs" => presentation_attrs(%{"class" => "mt-5"})
      },
      "action" => %{
        "attrs" => navigate_attrs(new_account_path, %{"class" => "btn btn-primary btn-sm"}),
        "icon" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"
            })
        },
        "text" => "Register provider account"
      }
    }
  end

  defp empty_state_presentation(false, _new_account_path), do: nil

  defp navigate_attrs(href, extra_attrs) do
    %{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => href
    }
    |> Map.merge(extra_attrs)
    |> presentation_attrs()
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
