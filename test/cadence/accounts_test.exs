defmodule Cadence.AccountsTest do
  use Cadence.UseCaseCase

  alias Cadence.Accounts
  alias Cadence.Domain.Accounts.Entities.User, as: UserEntity
  alias Cadence.Domain.Accounts.Entities.UserToken, as: UserTokenEntity
  alias Cadence.Test.Adapters.FakePasswordHasher
  alias Cadence.Test.Adapters.InMemoryTokenRepository

  alias Cadence.Accounts.User

  setup do
    Application.put_env(:cadence, :password_hasher, FakePasswordHasher)

    on_exit(fn ->
      Application.delete_env(:cadence, :password_hasher)
    end)

    :ok
  end

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %UserEntity{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %UserEntity{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise ArgumentError, fn ->
        # Use a valid UUID format that doesn't exist
        Accounts.get_user!(Ecto.UUID.generate())
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %UserEntity{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, reason} = Accounts.register_user(%{})
      assert reason == :email_required
    end

    test "validates email when given" do
      {:error, reason} = Accounts.register_user(%{email: "not valid"})
      assert reason == :invalid_email_format
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, reason} = Accounts.register_user(%{email: too_long})
      assert reason == :email_too_long
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, reason} = Accounts.register_user(valid_user_attributes(email: email))
      assert reason == :email_already_taken
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert {:ok, user_token} =
               InMemoryTokenRepository.find_by_token_and_context(
                 :crypto.hash(:sha256, token),
                 "change:current@example.com"
               )

      assert user_token.user_id == user.id
      # sent_to contains the NEW email (user.email), context contains the CURRENT email
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %UserEntity{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Accounts.get_user!(user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      assert InMemoryTokenRepository.list_all_for_user(user.id) == []
    end

    test "does not update email with invalid token", %{user: user} do
      # Invalid tokens return :not_found from the token repository
      assert {:error, _reason} = Accounts.update_user_email(user, "oops")
      assert Accounts.get_user!(user.id).email == user.email
      assert InMemoryTokenRepository.list_all_for_user(user.id) != []
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert {:error, :not_found} =
               Accounts.update_user_email(%{user | email: "current@example.com"}, token)

      assert Accounts.get_user!(user.id).email == user.email
      assert InMemoryTokenRepository.list_all_for_user(user.id) != []
    end

    test "does not update email if token expired", %{user: user, token: token} do
      :ok = expire_change_email_token(token, "change:#{user.email}")

      assert {:error, :expired} = Accounts.update_user_email(user, token)
      assert Accounts.get_user!(user.id).email == user.email
      assert InMemoryTokenRepository.list_all_for_user(user.id) != []
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :password) == "new valid password"
      assert is_nil(Ecto.Changeset.get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, reason} =
        Accounts.update_user_password(user, %{password: "not valid"})

      assert reason == :password_too_short
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, reason} = Accounts.update_user_password(user, %{password: too_long})
      assert reason == :password_too_long
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{password: "new valid password"})

      assert expired_tokens == []
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} =
        Accounts.update_user_password(user, %{password: "new valid password"})

      assert InMemoryTokenRepository.list_all_for_user(user.id) == []
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)

      assert {:ok, user_token} =
               InMemoryTokenRepository.find_by_token_and_context(token, "session")

      assert user_token.context == "session"
      assert user_token.authenticated_at != nil
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      :ok = expire_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      :ok = expire_login_token(token)
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {confirmed_user, expired_tokens}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert confirmed_user.confirmed_at
      # At least one token should be expired (the login token)
      assert length(expired_tokens) >= 1
    end

    test "returns user and empty tokens for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {returned_user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      assert returned_user.id == user.id
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture() |> set_password()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert {:ok, user_token} =
               InMemoryTokenRepository.find_by_token_and_context(
                 :crypto.hash(:sha256, token),
                 "login"
               )

      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  defp user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)
    confirm_user(user)
  end

  defp unconfirmed_user_fixture(attrs \\ %{}) do
    attrs = valid_user_attributes(attrs)
    {:ok, user} = Accounts.register_user(attrs)
    InMemoryTokenRepository.register_user(user)
    user
  end

  defp confirm_user(user) do
    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {confirmed_user, _expired_tokens}} = Accounts.login_user_by_magic_link(token)
    InMemoryTokenRepository.register_user(confirmed_user)
    confirmed_user
  end

  defp set_password(user) do
    {:ok, {updated_user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    InMemoryTokenRepository.register_user(updated_user)
    updated_user
  end

  defp valid_user_attributes(attrs) do
    attrs = normalize_attrs(attrs)

    defaults = %{
      email: unique_user_email(),
      system_admin: true
    }

    Map.merge(defaults, attrs)
  end

  defp unique_user_email, do: unique_email()
  defp valid_user_password, do: "hello world!"

  defp extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  defp generate_user_magic_link_token(user) do
    {:ok, token} = Cadence.Application.Accounts.MagicLinkOperations.generate_for_user(user)
    {token, nil}
  end

  defp expire_session_token(token) do
    expired_at = DateTime.add(DateTime.utc_now(), -30, :day)

    InMemoryTokenRepository.update_token(token, "session", %{
      created_at: expired_at,
      authenticated_at: expired_at
    })

    :ok
  end

  defp expire_login_token(token) do
    {:ok, hashed} = UserTokenEntity.verify_login_token(token)
    expired_at = DateTime.add(DateTime.utc_now(), -1, :day)
    InMemoryTokenRepository.update_token(hashed, "login", %{created_at: expired_at})
    :ok
  end

  defp expire_change_email_token(token, context) do
    {:ok, hashed} = UserTokenEntity.verify_change_email_token(token)
    expired_at = DateTime.add(DateTime.utc_now(), -10, :day)
    InMemoryTokenRepository.update_token(hashed, context, %{created_at: expired_at})
    :ok
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: Enum.into(attrs, %{})
  defp normalize_attrs(attrs), do: attrs
end
