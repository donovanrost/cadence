defmodule Cadence.Accounts.FixturePasswordsTest do
  @moduledoc """
  #242: the console e2e personas' password set. It's narrow by construction: only an existing
  apogee-qa persona, never the environment admin or a person's account, only with the dev/test
  flag on, at least 12 characters and not the public default. It signs out every session, records
  the act (never the value), and nothing in `lib/` calls it.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{AccountEventRow, Authentication, FixturePasswords, User}

  @old "an-older-fixture-pass"
  @new "a-fresh-ci-password-42"

  setup do
    persona =
      user!("qa-#{System.unique_integer([:positive])}@example.test", %{"fixture" => "apogee-qa"})

    person = user!("person-#{System.unique_integer([:positive])}@example.test", %{})
    %{persona: persona, person: person}
  end

  describe "set/3" do
    test "sets the password, signs out every session, and records the act without the value", c do
      {:ok, one} = Authentication.issue_browser_session(c.persona, nil)
      {:ok, two} = Authentication.issue_browser_session(c.persona, nil)

      assert :ok = FixturePasswords.set(c.persona.user_id, @new, "apogee-qa")

      assert {:ok, _session} = Authentication.sign_in(c.persona.email, @new)
      assert {:error, _} = Authentication.sign_in(c.persona.email, @old)

      for s <- [one, two],
          do: assert({:error, _} = Authentication.authenticate_user_session(s.session_token))

      assert [event] = events(c.persona.user_id)
      assert event.action == "password_changed"
      assert event.actor_id == "system:dev:apogee_qa_personas"
      refute inspect(event) =~ @new
    end

    test "refuses with the flag off, and writes nothing", c do
      Application.put_env(:cadence, :fixture_passwords, false)
      on_exit(fn -> Application.put_env(:cadence, :fixture_passwords, true) end)

      assert {:error, :fixture_passwords_disabled} =
               FixturePasswords.set(c.persona.user_id, @new, "apogee-qa")

      assert_unchanged(c.persona)
    end

    test "refuses the environment admin, another fixture, and a person's account", c do
      assert {:error, :password_managed_externally} =
               FixturePasswords.set("user_environment_admin", @new, "apogee-qa")

      assert {:error, :not_a_fixture_user} =
               FixturePasswords.set(c.persona.user_id, @new, "some-other-fixture")

      assert {:error, :not_a_fixture_user} =
               FixturePasswords.set(c.person.user_id, @new, "apogee-qa")

      assert {:error, :not_a_fixture_user} =
               FixturePasswords.set("user_missing", @new, "apogee-qa")

      assert_unchanged(c.persona)
      assert_unchanged(c.person)
    end

    test "refuses a short password and the public default", c do
      for bad <- ["short-pass", FixturePasswords.default_password()] do
        assert {:error, {:invalid, %{password: _}}} =
                 FixturePasswords.set(c.persona.user_id, bad, "apogee-qa")
      end

      assert_unchanged(c.persona)
    end
  end

  test "a failed credential write reaches the caller as field errors only: no hash, salt or password",
       c do
    leaky =
      %Ecto.Changeset{
        data: %Cadence.Accounts.UserLocalCredentialRow{},
        types: %{password_hash: :string, password_salt: :string},
        changes: %{password_hash: "HASH-SHOULD-NOT-LEAK", password_salt: "SALT-SHOULD-NOT-LEAK"},
        errors: [password_hash: {"is invalid", [value: "HASH-SHOULD-NOT-LEAK"]}],
        valid?: false
      }

    for failure <- [{:error, leaky}, {:error, {:boom, @new, "SALT-SHOULD-NOT-LEAK"}}] do
      result =
        FixturePasswords.set(c.persona.user_id, @new, "apogee-qa",
          store: fn _repo, _id, _password, _metadata -> failure end
        )

      assert {:error, reason} = result

      assert reason in [:password_not_set] or
               match?({:credential_invalid, %{password_hash: ["is invalid"]}}, reason)

      text = inspect(result)

      for secret <- ["HASH-SHOULD-NOT-LEAK", "SALT-SHOULD-NOT-LEAK", @new],
          do: refute(text =~ secret)
    end

    assert_unchanged(c.persona)
  end

  describe "the script's environment" do
    test "the password comes from E2E_PERSONA_PASSWORD, else the public default" do
      assert {:ok, @new, :env} =
               FixturePasswords.persona_password(%{"E2E_PERSONA_PASSWORD" => @new})

      default = FixturePasswords.default_password()
      assert {:ok, ^default, :default} = FixturePasswords.persona_password(%{})

      assert {:ok, ^default, :default} =
               FixturePasswords.persona_password(%{"E2E_PERSONA_PASSWORD" => ""})

      assert {:error, _} = FixturePasswords.persona_password(%{"E2E_PERSONA_PASSWORD" => "short"})
      assert {:error, _} = FixturePasswords.persona_password(%{"E2E_PERSONA_PASSWORD" => default})
    end

    test "a reset needs E2E_RESET_PERSONA_PASSWORDS=1 and a password of its own" do
      assert {:ok, false} = FixturePasswords.reset?(%{})

      assert {:ok, true} =
               FixturePasswords.reset?(%{
                 "E2E_RESET_PERSONA_PASSWORDS" => "1",
                 "E2E_PERSONA_PASSWORD" => @new
               })

      assert {:error, _} = FixturePasswords.reset?(%{"E2E_RESET_PERSONA_PASSWORDS" => "1"})

      assert {:error, _} =
               FixturePasswords.reset?(%{
                 "E2E_RESET_PERSONA_PASSWORDS" => "true",
                 "E2E_PERSONA_PASSWORD" => @new
               })

      assert {:error, _} =
               FixturePasswords.reset?(%{
                 "E2E_RESET_PERSONA_PASSWORDS" => "0",
                 "E2E_PERSONA_PASSWORD" => @new
               })
    end
  end

  test "nothing under lib/ calls it, so no route can reach it (ca-security)" do
    root = Path.expand("../../../..", __DIR__)

    callers =
      Path.wildcard(Path.join(root, "apps/*/lib/**/*.{ex,exs}"))
      |> Enum.reject(&String.ends_with?(&1, "accounts/fixture_passwords.ex"))
      |> Enum.filter(&(File.read!(&1) =~ "FixturePasswords"))

    assert callers == []
  end

  defp user!(email, metadata) do
    user =
      User.new(%{
        email: email,
        display_name: "Fixture test",
        capabilities: [],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: metadata
      })

    {:ok, user} = Authentication.upsert_user(Repo, user)
    :ok = Authentication.upsert_password_credential(Repo, user.user_id, @old, %{})
    user
  end

  defp events(user_id),
    do: Repo.all(from(e in AccountEventRow, where: e.user_id == ^user_id))

  defp assert_unchanged(user) do
    assert {:ok, _session} = Authentication.sign_in(user.email, @old)
    assert events(user.user_id) == []
  end
end
