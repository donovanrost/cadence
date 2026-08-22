defmodule CadenceSimulator.Provider.Configuration do
  @moduledoc "Immutable provider runtime configuration captured at application startup."

  alias CadenceSimulator.Provider.Auth

  @enforce_keys [:http, :store, :defaults, :auth]
  defstruct [:http, :store, :defaults, :auth]

  @type t :: %__MODULE__{
          http: keyword(),
          store: keyword(),
          defaults: keyword(),
          auth: keyword()
        }

  @spec snapshot() :: t()
  def snapshot do
    :cadence_simulator
    |> Application.get_all_env()
    |> new()
  end

  @spec new(keyword()) :: t()
  def new(config) when is_list(config) do
    http = Keyword.get(config, :provider_http, [])

    auth = [
      required?: Keyword.get(config, :provider_auth_required, false),
      provider_admin_api_token: Keyword.get(config, :provider_admin_api_token),
      provider_api_token: Keyword.get(config, :provider_api_token)
    ]

    Auth.validate_configuration!(
      Keyword.get(http, :enabled, false),
      Keyword.fetch!(auth, :required?),
      Keyword.get(auth, :provider_admin_api_token),
      Keyword.get(auth, :provider_api_token)
    )

    %__MODULE__{
      http: http,
      store:
        Keyword.get(config, :provider_store,
          path: Path.expand("var/cadence_simulator_provider.dets")
        ),
      defaults: Keyword.get(config, :provider_defaults, []),
      auth: auth
    }
  end

  @spec router_options(t()) :: keyword()
  def router_options(%__MODULE__{auth: auth}), do: [provider_auth: auth]

  @spec orchestrator_options(t()) :: keyword()
  def orchestrator_options(%__MODULE__{defaults: defaults}), do: [provider_defaults: defaults]
end
