defmodule Cadence.Control.Providers.MissionProviderWrites do
  @moduledoc """
  L12 mission-provider writes for the console: create from an account grant, validate, sync,
  archive. Mission admins (`:manage_mission`, checked by the domain writes).

  Validate and sync call the provider inline. Its client retries GETs and a sync makes five calls,
  so a slow provider could hold the request for minutes: both stop waiting after `@deadline_ms`,
  record the observation as failed ("didn't answer in time") and answer like any other refusal.
  The call isn't killed (it may be mid-query): it's unlinked and carries on, bounded by the
  client's own timeouts, and its outcome replaces the timeout in the provider's record.
  A provider that refuses is a result (`{:ok, provider, :failed}`), not an error; the provider's
  own record holds why (`Reads.Comms.ProviderHealth` words it).
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.{MissionProviderRegistration, ProviderError}
  alias Cadence.GroundNetworks.{ProviderAccountGrants, ProviderAccounts}
  alias Cadence.Management.Providers
  alias Cadence.Platform.ScopedReadUpdates

  @deadline_ms 25_000
  @refusals [
    :forbidden,
    :scope_mismatch,
    :authenticated_user_required,
    :mission_provider_not_found
  ]
  @policy_modes [
    %{key: "approval_required", label: "Ask before accepting provider changes"},
    %{key: "bounded_automatic", label: "Accept small changes automatically"}
  ]
  @deadline_behaviors [
    %{key: "retain_last_accepted", label: "Keep the last accepted booking"},
    %{key: "cancel_if_actionable", label: "Cancel it if it can still be cancelled"}
  ]
  @shift_fields ~w(maximum_earlier_start_shift_seconds maximum_later_start_shift_seconds maximum_earlier_end_shift_seconds maximum_later_end_shift_seconds minimum_retained_duration_seconds)

  @doc "The create sheet's choices: this mission's active grants and the policy vocabularies."
  @spec options(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def options(%Scope{} = scope, mission_id) do
    with :ok <- authorize(scope, mission_id) do
      {:ok,
       %{
         grants:
           scope.organization_id
           |> ProviderAccountGrants.list_for_mission(mission_id)
           |> Enum.flat_map(&grant_option(scope.organization_id, &1)),
         policy_modes: @policy_modes,
         deadline_behaviors: @deadline_behaviors
       }}
    end
  end

  @spec permissions(Scope.t(), binary()) :: [binary()]
  def permissions(scope, mission_id),
    do: if(authorize(scope, mission_id) == :ok, do: ["providers.manage"], else: [])

  @doc """
  `{grant_id, display_name, policy_mode, deadline_behavior?, permitted_resource_refs?,
  bounded?, expected_grant_version?}` → `{:ok, provider}`.
  """
  @spec create(Scope.t(), binary(), map()) :: {:ok, struct()} | {:error, term()}
  def create(%Scope{} = scope, mission_id, params) do
    with :ok <- authorize(scope, mission_id),
         {:ok, grant} <- grant(scope.organization_id, mission_id, params),
         {:ok, form} <- form(params, grant) do
      case MissionProviderRegistration.create(scope, mission_id, form) do
        {:ok, _provider} = created ->
          providers_changed(created, scope, mission_id)

        {:error, :invalid_delivery_policy} ->
          invalid(:bounded, "Check the shift limits.")

        {:error, :invalid_application_request} ->
          invalid(:display_name, "Use 1 to 120 characters.")

        {:error, :mission_provider_widens_account_guardrails} ->
          widens()

        result ->
          result
      end
    end
  end

  @doc "`{:ok, provider, :ok | :failed}`; `:failed` carries the reason in the provider's record."
  @spec validate(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, struct(), :ok | :failed} | {:error, term()}
  def validate(%Scope{} = scope, mission_id, provider_id, opts \\ []),
    do:
      observe(scope, mission_id, provider_id, "control_plane", opts, fn ->
        ControlProviders.validate_current(scope, mission_id, provider_id, call_opts(opts))
      end)

  @spec sync(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, struct(), :ok | :failed} | {:error, term()}
  def sync(%Scope{} = scope, mission_id, provider_id, opts \\ []),
    do:
      observe(scope, mission_id, provider_id, "sync", opts, fn ->
        ControlProviders.sync_current(scope, mission_id, provider_id, call_opts(opts))
      end)

  @doc "`{reason}` → the archived version. Works with a revoked grant (L12 defect 1)."
  @spec archive(Scope.t(), binary(), binary(), map()) :: {:ok, struct()} | {:error, term()}
  def archive(%Scope{} = scope, mission_id, provider_id, params) do
    case text(params["reason"], 500) do
      nil ->
        invalid(:reason, "Say why.")

      reason ->
        scope
        |> Providers.archive_provider(mission_id, provider_id, reason)
        |> providers_changed(scope, mission_id)
    end
  end

  defp observe(scope, mission_id, provider_id, observation, opts, call) do
    task = Task.async(call)

    case Task.yield(task, Keyword.get(opts, :deadline_ms, @deadline_ms)) || Task.ignore(task) do
      {:ok, {:ok, provider}} -> {:ok, provider, :ok}
      {:ok, {:error, reason}} when reason in @refusals -> {:error, reason}
      {:ok, {:error, _recorded}} -> current(scope, mission_id, provider_id, :failed)
      {:exit, reason} -> {:error, {:provider_call_failed, reason}}
      nil -> timed_out(scope, mission_id, provider_id, observation)
    end
  end

  defp timed_out(scope, mission_id, provider_id, observation) do
    timeout = %ProviderError{
      category: :known_timeout,
      detail: "The provider didn't answer in time.",
      retryable: true
    }

    with {:ok, provider} <-
           Providers.fetch_provider(scope.organization_id, mission_id, provider_id) do
      GroundNetworks.record_provider_failure(provider, observation, timeout)
      current(scope, mission_id, provider_id, :failed)
    end
  end

  defp current(scope, mission_id, provider_id, outcome) do
    with {:ok, provider} <-
           Providers.fetch_provider(scope.organization_id, mission_id, provider_id),
         do: {:ok, provider, outcome}
  end

  defp call_opts(opts), do: Keyword.drop(opts, [:deadline_ms])

  # A created or archived provider changes the providers read: its `providers` live update
  # (#972). Validate and sync publish from `GroundNetworks`, where their outcome is recorded.
  defp providers_changed({:ok, _provider} = result, scope, mission_id) do
    ScopedReadUpdates.publish(:providers_changed, scope.organization_id, mission_id)
    result
  end

  defp providers_changed(result, _scope, _mission_id), do: result

  defp authorize(scope, mission_id),
    do:
      Policy.authorize(scope, :manage_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      })

  defp grant(organization_id, mission_id, params) do
    with {:ok, id} <- required(params, "grant_id"),
         {:ok, grant} <- active_grant(organization_id, id),
         true <- grant.mission_id == mission_id || {:error, :grant_not_for_mission} do
      case params["expected_grant_version"] do
        nil -> {:ok, grant}
        version when version == grant.version -> {:ok, grant}
        _stale -> {:error, {:grant_changed, %{version: grant.version}}}
      end
    else
      {:error, :grant_not_for_mission} ->
        invalid(:grant_id, "Choose one of this mission's grants.")

      error ->
        error
    end
  end

  defp active_grant(organization_id, id) do
    case ProviderAccountGrants.fetch_active_for_system(organization_id, id) do
      {:ok, grant} -> {:ok, grant}
      {:error, :provider_account_grant_revoked} -> {:error, :grant_revoked}
      {:error, _not_found} -> invalid(:grant_id, "Choose one of this mission's grants.")
    end
  end

  # The registration takes the legacy form's strings.
  defp form(params, grant) do
    bounded = if is_map(params["bounded"]), do: params["bounded"], else: %{}

    with {:ok, name} <- name(params),
         {:ok, mode} <- member(params, "policy_mode", @policy_modes, nil),
         {:ok, deadline} <-
           member(params, "deadline_behavior", @deadline_behaviors, "retain_last_accepted"),
         {:ok, refs} <- names(params["permitted_resource_refs"], :permitted_resource_refs),
         {:ok, substitutions} <-
           names(bounded["approved_station_substitutions"], :approved_station_substitutions),
         {:ok, shifts} <- shifts(bounded, mode) do
      {:ok,
       %{
         "provider_account_grant_id" => grant.provider_account_grant_id,
         "provider_account_grant_version" => Integer.to_string(grant.version),
         "display_name" => name,
         "policy_mode" => mode,
         "deadline_behavior" => deadline,
         "permitted_resource_refs" => Enum.join(refs, ","),
         "approved_station_substitutions" => Enum.join(substitutions, ",")
       }
       |> Map.merge(shifts)}
    end
  end

  defp name(params) do
    case text(params["display_name"], 120) do
      nil -> invalid(:display_name, "Use 1 to 120 characters.")
      name -> {:ok, name}
    end
  end

  defp member(params, key, choices, default) do
    value = params[key] || default

    if Enum.any?(choices, &(&1.key == value)),
      do: {:ok, value},
      else: invalid(key, "Choose one of the options.")
  end

  defp names(nil, _field), do: {:ok, []}

  defp names(values, field) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and &1 != "" and not String.contains?(&1, ","))),
      do: {:ok, Enum.uniq(values)},
      else: invalid(field, "Use a list of names.")
  end

  defp names(_values, field), do: invalid(field, "Use a list of names.")

  defp shifts(_bounded, "approval_required"), do: {:ok, %{}}

  defp shifts(bounded, "bounded_automatic") do
    Enum.reduce_while(@shift_fields, {:ok, %{}}, fn key, {:ok, acc} ->
      case bounded[key] do
        nil -> {:cont, {:ok, acc}}
        n when is_integer(n) and n >= 0 -> {:cont, {:ok, Map.put(acc, key, Integer.to_string(n))}}
        _bad -> {:halt, invalid(:bounded, "#{key} must be a whole number of seconds.")}
      end
    end)
  end

  defp grant_option(organization_id, grant) do
    case ProviderAccounts.fetch_for_system(organization_id, grant.provider_account_id) do
      {:ok, account, version} ->
        [
          %{
            id: grant.provider_account_grant_id,
            version: grant.version,
            account: %{
              id: account.provider_account_id,
              name: account.display_name,
              provider: %{key: version.provider_type, label: label(version.provider_type)}
            },
            allowed_stations: list(grant.restrictions, "allowed_stations"),
            allowed_services: list(grant.restrictions, "allowed_services")
          }
        ]

      _gone ->
        []
    end
  end

  defp list(map, key) do
    case Map.get(map || %{}, key) do
      [_ | _] = values -> values
      _none -> nil
    end
  end

  defp label(type), do: type |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp widens,
    do: invalid(:permitted_resource_refs, "Pick only stations the account grant allows.")

  defp invalid(field, message), do: {:error, {:invalid_params, %{field => message}}}

  defp required(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> invalid(key, "Required.")
    end
  end

  defp text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text when byte_size(text) <= max -> text
      _long -> nil
    end
  end

  defp text(_value, _max), do: nil
end
