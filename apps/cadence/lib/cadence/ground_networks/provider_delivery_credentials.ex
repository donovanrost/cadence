defmodule Cadence.GroundNetworks.ProviderDeliveryCredentials do
  @moduledoc """
  Registers certificate fingerprints for inbound delivery. The opaque reference belongs to one
  mission, provider grant and stable delivery binding. The binding ID is the transport ID, which
  survives transport and materialized provider-profile versions.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.{Transport, TransportStore}
  alias Cadence.GroundNetworks.{MissionProviders, ProviderAccountGrants, ProviderAccounts}
  alias Cadence.GroundNetworks.{ProviderAudit, ProviderAuditEntry}
  alias Cadence.GroundNetworks.ProviderDeliveryCredentials.{CredentialRow, GenerationRow, Issuer}
  alias Cadence.Ids
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @overlap_hours 24
  @reason_codes %{
    issue: ~w(initial_enrollment),
    rotate: ~w(scheduled_rotation suspected_compromise operator_requested),
    revoke: ~w(suspected_compromise retired_binding end_overlap operator_requested)
  }

  def issue(scope, mission, provider, binding, params, opts \\ []),
    do: enroll(scope, mission, provider, binding, params, opts, :issue)

  def rotate(scope, mission, provider, binding, params, opts \\ []),
    do: enroll(scope, mission, provider, binding, params, opts, :rotate)

  def show(%Scope{} = scope, mission, provider, binding) do
    with :ok <- authorize(scope, mission, :issue),
         %CredentialRow{} = credential <- Repo.one(scoped(scope, mission, provider, binding)) do
      {:ok, summarize(credential, generations(credential))}
    else
      nil -> {:error, :delivery_credential_not_found}
      error -> error
    end
  end

  def revoke(%Scope{} = scope, mission, provider, binding, params) do
    with :ok <- authorize(scope, mission, :revoke),
         {:ok, reason} <- reason(:revoke, params),
         {:ok, target} <- revocation_target(params, reason) do
      Repo.transact(fn ->
        persist_revocation(scope, mission, provider, binding, target, reason)
      end)
      |> changed(scope, mission)
    end
  end

  defp persist_revocation(scope, mission, provider, binding, target, reason) do
    with {:ok, credential} <- lock_binding(scope, mission, provider, binding),
         {:ok, credential, revoked} <- revoke_generations(credential, target, DateTime.utc_now()),
         {:ok, _} <- audit(scope, credential, :revoke, reason, revoked) do
      {:ok, summarize(credential, generations(credential))}
    end
  end

  defp enroll(%Scope{} = scope, mission, provider_id, binding, params, opts, action) do
    with :ok <- authorize(scope, mission, action),
         :ok <- validate_binding(binding),
         {:ok, reason} <- reason(action, params),
         {:ok, expected} <- expected_generation(action, params),
         {:ok, key} <- Issuer.public_key(params["csr_pem"]) do
      enrollment = %{action: action, key: key, expected: expected, opts: opts, reason: reason}

      Repo.transact(fn ->
        persist_enrollment(scope, mission, provider_id, binding, enrollment)
      end)
      |> changed(scope, mission)
    end
  end

  defp persist_enrollment(scope, mission, provider_id, binding, enrollment) do
    %{action: action, reason: reason} = enrollment
    org = scope.organization_id

    with {:ok, provider} <- live_provider(org, mission, provider_id),
         :ok <- require_live_binding(org, mission, provider_id, binding),
         {:ok, credential} <- enrollment_binding(scope, provider, binding, action),
         :ok <- validate_provider(credential, provider),
         {:ok, leaf, revoked} <- install_leaf(credential, enrollment),
         {:ok, _} <- audit(scope, credential, action, reason, [leaf.fingerprint | revoked]) do
      {:ok,
       %{
         credential: summarize(credential, generations(credential)),
         certificate_pem: leaf.certificate_pem,
         issuer_certificate_pem: leaf.issuer_certificate_pem
       }}
    end
  end

  defp require_live_binding(org, mission, provider_id, binding) do
    case TransportStore.lock_current_transport(org, mission, binding) do
      {:ok,
       %Transport{
         origin: :provider_managed,
         lifecycle_state: :active,
         mission_provider_id: ^provider_id
       }} ->
        :ok

      _unavailable ->
        {:error, :delivery_binding_unavailable}
    end
  end

  defp enrollment_binding(scope, provider, binding, :issue) do
    candidate = %CredentialRow{
      credential_ref: Ids.new("delivery_credential"),
      organization_id: scope.organization_id,
      mission_id: provider.mission_id,
      provider_id: provider.provider_id,
      provider_account_id: provider.provider_account_id,
      provider_account_grant_id: provider.provider_account_grant_id,
      provider_binding_id: binding
    }

    with {:ok, _} <-
           Repo.insert(candidate,
             on_conflict: :nothing,
             conflict_target: [:organization_id, :mission_id, :provider_binding_id]
           ) do
      lock_binding(scope, provider.mission_id, provider.provider_id, binding)
    end
  end

  defp enrollment_binding(scope, provider, binding, :rotate),
    do: lock_binding(scope, provider.mission_id, provider.provider_id, binding)

  defp lock_binding(scope, mission, provider, binding) do
    case scoped(scope, mission, provider, binding) |> lock("FOR UPDATE") |> Repo.one() do
      nil -> {:error, :delivery_credential_not_found}
      %CredentialRow{retired_at: %DateTime{}} -> {:error, :delivery_binding_retired}
      credential -> {:ok, credential}
    end
  end

  defp scoped(scope, mission, provider, binding) do
    from(row in CredentialRow,
      where:
        row.organization_id == ^scope.organization_id and row.mission_id == ^mission and
          row.provider_id == ^provider and row.provider_binding_id == ^binding
    )
  end

  defp install_leaf(credential, enrollment) do
    %{action: action, key: key, expected: expected, opts: opts, reason: reason} = enrollment
    now = DateTime.utc_now()
    generations = live_generations(credential)
    current = Enum.find(generations, &(&1.state == :current))
    previous = Enum.find(generations, &(&1.state == :previous))
    generation = (Repo.aggregate(generation_query(credential), :max, :generation) || 0) + 1

    key_fingerprint = Issuer.key_fingerprint(key)

    with :ok <- allow_enrollment(action, current, expected),
         :ok <- refuse_reused_key(key_fingerprint),
         {:ok, leaf} <- Issuer.issue(key, credential.credential_ref, now, issuer_options(opts)),
         {:ok, revoked} <- advance_overlap(reason, current, previous, now),
         :ok <- insert_generation(credential, generation, leaf, key_fingerprint) do
      {:ok, leaf, revoked}
    end
  end

  defp refuse_reused_key(fingerprint) do
    if Repo.exists?(
         from(row in GenerationRow, where: row.public_key_fingerprint == ^fingerprint)
       ),
       do: {:error, :invalid_delivery_csr},
       else: :ok
  end

  defp insert_generation(credential, generation, leaf, key_fingerprint) do
    row = %GenerationRow{
      credential_ref: credential.credential_ref,
      fingerprint: leaf.fingerprint,
      public_key_fingerprint: key_fingerprint,
      generation: generation,
      state: :current,
      expires_at: leaf.expires_at
    }

    row
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:public_key_fingerprint,
      name: :provider_delivery_certificate_public_key_idx
    )
    |> Repo.insert()
    |> case do
      {:ok, _row} -> :ok
      {:error, _changeset} -> {:error, :invalid_delivery_csr}
    end
  end

  defp allow_enrollment(:issue, nil, _expected), do: :ok

  defp allow_enrollment(:issue, _current, _expected),
    do: {:error, :delivery_credential_already_issued}

  defp allow_enrollment(:rotate, nil, _expected), do: {:error, :delivery_credential_not_issued}
  defp allow_enrollment(:rotate, %{generation: generation}, generation), do: :ok
  defp allow_enrollment(:rotate, _current, _expected), do: {:error, :version_conflict}

  defp expected_generation(:issue, _params), do: {:ok, nil}

  defp expected_generation(:rotate, %{"expected_generation" => generation})
       when is_integer(generation) and generation > 0,
       do: {:ok, generation}

  defp expected_generation(:rotate, _params), do: {:error, :invalid_delivery_generation}

  defp issuer_options(opts),
    do: Keyword.merge(Application.get_env(:cadence, :provider_delivery_issuer, []), opts)

  defp advance_overlap("suspected_compromise", current, previous, now),
    do: deny_generations(Enum.reject([current, previous], &is_nil/1), now)

  defp advance_overlap(_reason, nil, _previous, _now), do: {:ok, []}

  defp advance_overlap(_reason, current, previous, now) do
    cutoff = Enum.min([current.expires_at, DateTime.add(now, @overlap_hours, :hour)], DateTime)
    {microsecond, _precision} = cutoff.microsecond
    cutoff = %{cutoff | microsecond: {microsecond, 6}}

    with {:ok, revoked} <- deny_generation(previous, now),
         {:ok, _} <-
           Repo.update(
             Ecto.Changeset.change(current,
               state: :previous,
               overlap_ends_at: cutoff
             )
           ) do
      {:ok, Enum.map(List.wrap(revoked), & &1.fingerprint)}
    end
  end

  defp revoke_generations(credential, :binding, now) do
    live = live_generations(credential)

    with {:ok, revoked} <- deny_generations(live, now),
         {:ok, retired} <- Repo.update(Ecto.Changeset.change(credential, retired_at: now)) do
      {:ok, retired, revoked}
    end
  end

  defp revoke_generations(credential, {fingerprint, keep_previous?}, now) do
    live = live_generations(credential)

    with %GenerationRow{} = target <- Enum.find(live, &(&1.fingerprint == fingerprint)),
         :ok <- check_keep_previous(target, keep_previous?),
         rows = if(target.state == :current and not keep_previous?, do: live, else: [target]),
         {:ok, revoked} <- deny_generations(rows, now) do
      {:ok, credential, revoked}
    else
      nil -> {:error, :delivery_generation_not_found}
      error -> error
    end
  end

  defp deny_generations(rows, now) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, fingerprints} ->
      case deny_generation(row, now) do
        {:ok, _} -> {:cont, {:ok, [row.fingerprint | fingerprints]}}
        error -> {:halt, error}
      end
    end)
  end

  defp deny_generation(nil, _now), do: {:ok, nil}

  defp deny_generation(row, now),
    do: Repo.update(Ecto.Changeset.change(row, state: :revoked, revoked_at: now))

  defp generation_query(credential),
    do: from(row in GenerationRow, where: row.credential_ref == ^credential.credential_ref)

  defp live_generations(credential) do
    credential
    |> generation_query()
    |> where([row], row.state in [:current, :previous])
    |> Repo.all()
  end

  defp generations(credential) do
    live = live_generations(credential)

    latest_revoked =
      Repo.one(
        from(row in generation_query(credential),
          where: row.state == :revoked,
          order_by: [desc: row.generation],
          limit: 1
        )
      )

    Enum.sort_by(live ++ List.wrap(latest_revoked), & &1.generation, :desc)
  end

  defp summarize(credential, generations) do
    now = DateTime.utc_now()

    %{
      credential_ref: credential.credential_ref,
      provider_binding_id: credential.provider_binding_id,
      retired_at: credential.retired_at,
      generations: Enum.map(generations, &summarize_generation(&1, now))
    }
  end

  defp summarize_generation(generation, now) do
    generation
    |> Map.take([:fingerprint, :generation, :state, :expires_at, :overlap_ends_at, :revoked_at])
    |> Map.put(:within_acceptance_window, within_acceptance_window?(generation, now))
  end

  defp within_acceptance_window?(%GenerationRow{state: :revoked}, _now), do: false

  defp within_acceptance_window?(leaf, now) do
    DateTime.after?(leaf.expires_at, now) and
      (is_nil(leaf.overlap_ends_at) or DateTime.after?(leaf.overlap_ends_at, now))
  end

  defp live_provider(org, mission, id) do
    with {:ok,
          %{
            lifecycle_state: :active,
            provider_account_id: account_id,
            provider_account_grant_id: grant_id
          } = provider} <-
           MissionProviders.fetch_provider(org, mission, id),
         true <- is_binary(grant_id) and is_binary(account_id),
         {:ok, %{mission_id: ^mission, provider_account_id: ^account_id}} <-
           ProviderAccountGrants.fetch_active_for_system(org, grant_id),
         {:ok, %{lifecycle_state: :active}, _} <-
           ProviderAccounts.fetch_for_system(org, account_id) do
      {:ok, provider}
    else
      _inactive -> {:error, :delivery_binding_unavailable}
    end
  end

  defp validate_provider(credential, provider) do
    if credential.provider_account_id == provider.provider_account_id and
         credential.provider_account_grant_id == provider.provider_account_grant_id,
       do: :ok,
       else: {:error, :delivery_binding_unavailable}
  end

  defp audit(scope, credential, action, reason, fingerprints) do
    ProviderAudit.append(
      ProviderAuditEntry.new(%{
        organization_id: credential.organization_id,
        mission_id: credential.mission_id,
        provider_account_id: credential.provider_account_id,
        provider_account_grant_id: credential.provider_account_grant_id,
        provider_id: credential.provider_id,
        credential_ref: credential.credential_ref,
        action: "provider_delivery_credential.#{action}",
        outcome: "succeeded",
        actor_document: Scope.audit_actor(scope),
        decision_document: %{
          provider_binding_id: credential.provider_binding_id,
          fingerprints: fingerprints,
          reason: reason
        }
      })
    )
  end

  defp changed(result, scope, mission),
    do:
      ScopedReadUpdates.publish_result(
        result,
        :provider_delivery_credentials_changed,
        scope.organization_id,
        mission
      )

  defp authorize(scope, mission, action) do
    permission =
      case action do
        :issue -> :"provider_delivery_credential.issue"
        :rotate -> :"provider_delivery_credential.rotate"
        :revoke -> :"provider_delivery_credential.revoke"
      end

    Policy.authorize(scope, permission, %{
      organization_id: scope.organization_id,
      mission_id: mission
    })
  end

  defp reason(action, %{"reason" => reason}) do
    if reason in Map.fetch!(@reason_codes, action),
      do: {:ok, reason},
      else: {:error, :invalid_delivery_credential_reason}
  end

  defp reason(_action, _params), do: {:error, :invalid_delivery_credential_reason}

  defp validate_binding(id) do
    if Ids.valid_identifier?(id), do: :ok, else: {:error, :invalid_delivery_binding}
  end

  defp revocation_target(%{"keep_previous" => true}, "suspected_compromise"),
    do: {:error, :invalid_delivery_revocation_target}

  defp revocation_target(%{"fingerprint" => fingerprint} = params, _reason)
       when is_binary(fingerprint) and byte_size(fingerprint) == 64 do
    case Map.get(params, "keep_previous", false) do
      keep when is_boolean(keep) -> {:ok, {fingerprint, keep}}
      _invalid -> {:error, :invalid_delivery_revocation_target}
    end
  end

  defp revocation_target(%{"fingerprint" => _}, _reason),
    do: {:error, :invalid_delivery_revocation_target}

  defp revocation_target(%{"keep_previous" => _}, _reason),
    do: {:error, :invalid_delivery_revocation_target}

  defp revocation_target(%{"target" => "binding"}, _reason), do: {:ok, :binding}
  defp revocation_target(_params, _reason), do: {:error, :invalid_delivery_revocation_target}

  defp check_keep_previous(%{state: :current}, _), do: :ok
  defp check_keep_previous(_target, false), do: :ok
  defp check_keep_previous(_target, true), do: {:error, :invalid_delivery_revocation_target}
end
