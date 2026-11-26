# #242: compiled only for :dev and :test (api-ops), so a release carries no password-set that
# skips the current password. Under :dev and :test it is also inert unless
# `config :cadence, :fixture_passwords` is true (ca-security), set only in dev.exs and test.exs.
if Mix.env() in [:dev, :test] do
  defmodule Cadence.Accounts.FixturePasswords do
    @moduledoc """
    The console e2e personas' passwords (dev/apogee_qa_personas.exs, #242), for CI to set its own
    random password through the app's credential path, never raw SQL.

    - `set/3` sets the password of an EXISTING user the persona seed made (the user row's
      `metadata["fixture"] == "apogee-qa"`; only server code sets a user's metadata). It refuses
      the environment admin, any other user or fixture, and a password under 12 characters. In
      one transaction it stores the new credential, signs out every session of the user, and
      records `password_changed` for the audit with the system actor
      `"system:dev:apogee_qa_personas"` (no session made the change). The password is never
      logged or recorded.
    - `persona_password/1` and `reset?/1` read the script's environment, so its rules are
      tested here.
    """

    alias Cadence.Accounts.{AccountEvents, Authentication, UserRow}
    alias Cadence.Repo

    @environment_admin "user_environment_admin"
    @fixture "apogee-qa"
    @actor "system:dev:apogee_qa_personas"
    @min_password 12

    @doc """
    The persona password from `env` (`System.get_env/0`'s map): `{:ok, password, :env}` from a
    set `E2E_PERSONA_PASSWORD`, or `{:error, reason}` when missing or too short.
    """
    @spec persona_password(map()) :: {:ok, String.t(), :env} | {:error, String.t()}
    def persona_password(env) do
      case Map.get(env, "E2E_PERSONA_PASSWORD", "") do
        "" -> {:error, "E2E_PERSONA_PASSWORD is required"}
        value -> if long_enough?(value), do: {:ok, value, :env}, else: {:error, too_short()}
      end
    end

    @doc """
    Whether `env` asks for a reset: `{:ok, false}` when `E2E_RESET_PERSONA_PASSWORDS` is unset,
    `{:ok, true}` for `"1"` with `E2E_PERSONA_PASSWORD` set, else `{:error, reason}` (any other
    value, or a reset with no password of its own).
    """
    @spec reset?(map()) :: {:ok, boolean()} | {:error, String.t()}
    def reset?(env) do
      case {Map.get(env, "E2E_RESET_PERSONA_PASSWORDS"), Map.get(env, "E2E_PERSONA_PASSWORD", "")} do
        {nil, _password} ->
          {:ok, false}

        {"1", ""} ->
          {:error, "E2E_RESET_PERSONA_PASSWORDS=1 needs E2E_PERSONA_PASSWORD"}

        {"1", _password} ->
          {:ok, true}

        {other, _password} ->
          {:error, "E2E_RESET_PERSONA_PASSWORDS must be 1, not #{inspect(other)}"}
      end
    end

    @doc "Sets an apogee-qa persona's password; see the moduledoc."
    @spec set(binary(), binary(), binary(), keyword()) ::
            :ok
            | {:error,
               :fixture_passwords_disabled
               | :password_managed_externally
               | :not_a_fixture_user
               | {:invalid, map()}
               | {:credential_invalid, map()}
               | :password_not_set}
    def set(user_id, password, fixture, opts \\ [])
        when is_binary(user_id) and is_binary(password) do
      # `store:` is the credential writer (a test forces its failure; api-ops, #625).
      store = Keyword.get(opts, :store, &Authentication.upsert_password_credential/4)

      with :ok <- allowed(user_id, password, fixture) do
        Repo.transaction(fn -> set_locked(user_id, password, store) end)
        |> case do
          {:ok, :ok} -> :ok
          {:error, reason} -> {:error, safe(reason)}
        end
      end
    end

    # What a caller (and a public CI log) may see of a failure: a changeset becomes its fields'
    # message templates only, never its changes (the hash, the salt) or values; a known reason
    # stays; anything else is `:password_not_set` (api-ops, #625).
    defp safe(%Ecto.Changeset{} = changeset),
      do:
        {:credential_invalid,
         Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)}

    defp safe(reason) when reason in [:not_a_fixture_user], do: reason
    defp safe(_reason), do: :password_not_set

    # Each refusal before anything is read or written.
    defp allowed(user_id, password, fixture) do
      cond do
        Application.get_env(:cadence, :fixture_passwords, false) != true ->
          {:error, :fixture_passwords_disabled}

        user_id == @environment_admin ->
          {:error, :password_managed_externally}

        fixture != @fixture ->
          {:error, :not_a_fixture_user}

        not long_enough?(password) ->
          {:error, {:invalid, %{password: too_short()}}}

        true ->
          :ok
      end
    end

    defp set_locked(user_id, password, store) do
      with %UserRow{} = row <- Repo.get(UserRow, user_id),
           # The stored metadata is a wrapped JSON document; read it as the domain does.
           %{metadata: %{"fixture" => @fixture}} <- UserRow.to_domain(row),
           :ok <-
             store.(Repo, user_id, password, %{"fixture" => @fixture}),
           :ok <- Authentication.revoke_all_user_sessions(Repo, user_id) do
        AccountEvents.record(user_id, @actor, "password_changed", %{
          "all_sessions_signed_out" => true
        })
      else
        {:error, reason} -> Repo.rollback(reason)
        _not_a_fixture_user -> Repo.rollback(:not_a_fixture_user)
      end
    end

    defp long_enough?(password), do: String.length(password) >= @min_password
    defp too_short, do: "must be at least #{@min_password} characters"
  end
end
