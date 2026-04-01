defmodule Cadence.Domain.Accounts.Entities.UserTest do
  use Cadence.PureCase

  alias Cadence.Domain.Accounts.Entities.User

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        email: "user-#{unique_integer()}@example.com",
        organization_id: Ecto.UUID.generate()
      },
      overrides
    )
  end

  describe "new/1" do
    test "creates a user with valid attributes" do
      attrs = valid_attrs()
      assert {:ok, user} = User.new(attrs)

      assert user.email == String.downcase(attrs.email)
      assert user.organization_id == attrs.organization_id
      assert user.role == :member
      assert user.system_admin == false
    end

    test "sets default role to member" do
      assert {:ok, user} = User.new(valid_attrs())
      assert user.role == :member
    end

    test "sets system_admin to false by default" do
      assert {:ok, user} = User.new(valid_attrs())
      assert user.system_admin == false
    end

    test "allows custom role" do
      attrs = valid_attrs(%{role: :admin})
      assert {:ok, user} = User.new(attrs)
      assert user.role == :admin
    end

    test "allows system_admin users without organization_id" do
      attrs = %{email: "admin@example.com", system_admin: true}
      assert {:ok, user} = User.new(attrs)
      assert user.system_admin == true
      assert user.organization_id == nil
    end

    test "fails with missing email" do
      attrs = valid_attrs() |> Map.delete(:email)
      assert {:error, :email_required} = User.new(attrs)
    end

    test "fails with missing organization_id for non-system-admin" do
      attrs = %{email: "user@example.com"}
      assert {:error, :organization_id_required} = User.new(attrs)
    end

    test "fails with invalid email format" do
      attrs = valid_attrs(%{email: "invalid-email"})
      assert {:error, :invalid_email_format} = User.new(attrs)
    end

    test "fails with empty email" do
      attrs = valid_attrs(%{email: ""})
      assert {:error, :email_required} = User.new(attrs)
    end

    test "normalizes email to lowercase" do
      attrs = valid_attrs(%{email: "User@Example.COM"})
      assert {:ok, user} = User.new(attrs)
      assert user.email == "user@example.com"
    end

    test "trims email whitespace" do
      attrs = valid_attrs(%{email: "  user@example.com  "})
      assert {:ok, user} = User.new(attrs)
      assert user.email == "user@example.com"
    end
  end

  describe "update_email/2" do
    test "updates user email" do
      {:ok, user} = User.new(valid_attrs())
      new_email = "newemail@example.com"
      assert {:ok, updated} = User.update_email(user, new_email)
      assert updated.email == new_email
    end

    test "fails when email unchanged" do
      {:ok, user} = User.new(valid_attrs(%{email: "user@example.com"}))
      assert {:error, :email_not_changed} = User.update_email(user, "user@example.com")
    end

    test "fails with invalid email format" do
      {:ok, user} = User.new(valid_attrs())
      assert {:error, :invalid_email_format} = User.update_email(user, "invalid")
    end
  end

  describe "confirm/1" do
    test "sets confirmed_at timestamp" do
      {:ok, user} = User.new(valid_attrs())
      assert user.confirmed_at == nil
      assert {:ok, confirmed} = User.confirm(user)
      assert confirmed.confirmed_at != nil
    end
  end

  describe "validate_password/1" do
    test "returns :ok for valid password" do
      assert :ok = User.validate_password("valid_password_123")
    end

    test "returns error for password too short" do
      assert {:error, :password_too_short} = User.validate_password("short")
    end

    test "returns error for password too long" do
      long_password = String.duplicate("a", 100)
      assert {:error, :password_too_long} = User.validate_password(long_password)
    end

    test "returns error for non-string" do
      assert {:error, :invalid_password} = User.validate_password(nil)
    end
  end

  describe "set_hashed_password/2" do
    test "sets the hashed password" do
      {:ok, user} = User.new(valid_attrs())
      assert user.hashed_password == nil

      {:ok, updated} = User.set_hashed_password(user, "hashed_value")
      assert updated.hashed_password == "hashed_value"
    end
  end

  describe "update_role/2" do
    test "updates user role" do
      {:ok, user} = User.new(valid_attrs())
      assert {:ok, updated} = User.update_role(user, :admin)
      assert updated.role == :admin
    end

    test "fails with invalid role" do
      {:ok, user} = User.new(valid_attrs())
      assert {:error, :invalid_role} = User.update_role(user, :invalid)
    end
  end

  describe "make_system_admin/1" do
    test "sets system_admin to true" do
      {:ok, user} = User.new(valid_attrs())
      assert user.system_admin == false

      {:ok, admin} = User.make_system_admin(user)
      assert admin.system_admin == true
    end
  end

  describe "revoke_system_admin/1" do
    test "sets system_admin to false" do
      {:ok, user} = User.new(valid_attrs(%{system_admin: true}))
      {:ok, revoked} = User.revoke_system_admin(user)
      assert revoked.system_admin == false
    end
  end

  describe "predicates" do
    test "confirmed?/1 returns true for confirmed users" do
      {:ok, user} = User.new(valid_attrs())
      {:ok, confirmed} = User.confirm(user)
      assert User.confirmed?(confirmed) == true
    end

    test "confirmed?/1 returns false for unconfirmed users" do
      {:ok, user} = User.new(valid_attrs())
      assert User.confirmed?(user) == false
    end

    test "system_admin?/1 returns true for system admins" do
      {:ok, user} = User.new(valid_attrs(%{system_admin: true}))
      assert User.system_admin?(user) == true
    end

    test "system_admin?/1 returns false for regular users" do
      {:ok, user} = User.new(valid_attrs())
      assert User.system_admin?(user) == false
    end

    test "has_role_at_least?/2 checks role hierarchy" do
      {:ok, member} = User.new(valid_attrs(%{role: :member}))
      {:ok, admin} = User.new(valid_attrs(%{role: :admin}))
      {:ok, owner} = User.new(valid_attrs(%{role: :owner}))

      assert User.has_role_at_least?(owner, :admin) == true
      assert User.has_role_at_least?(admin, :member) == true
      assert User.has_role_at_least?(member, :admin) == false
    end

    test "has_role_at_least?/2 returns true for system admins" do
      {:ok, sysadmin} = User.new(valid_attrs(%{system_admin: true}))
      assert User.has_role_at_least?(sysadmin, :owner) == true
    end

    test "owner?/1 returns true for owners" do
      {:ok, owner} = User.new(valid_attrs(%{role: :owner}))
      assert User.owner?(owner) == true
    end

    test "admin_or_higher?/1 returns true for admins and owners" do
      {:ok, admin} = User.new(valid_attrs(%{role: :admin}))
      {:ok, owner} = User.new(valid_attrs(%{role: :owner}))
      {:ok, member} = User.new(valid_attrs(%{role: :member}))

      assert User.admin_or_higher?(admin) == true
      assert User.admin_or_higher?(owner) == true
      assert User.admin_or_higher?(member) == false
    end

    test "has_password?/1 returns true when password is set" do
      {:ok, user} = User.new(valid_attrs())
      {:ok, with_password} = User.set_hashed_password(user, "hashed")
      assert User.has_password?(with_password) == true
    end

    test "has_password?/1 returns false when no password" do
      {:ok, user} = User.new(valid_attrs())
      assert User.has_password?(user) == false
    end
  end

  describe "from_persistence/1" do
    test "reconstructs user from persisted data" do
      attrs = %{
        id: Ecto.UUID.generate(),
        email: "user@example.com",
        hashed_password: "hashed",
        confirmed_at: DateTime.utc_now(),
        role: "admin",
        system_admin: true,
        organization_id: Ecto.UUID.generate(),
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      user = User.from_persistence(attrs)

      assert user.id == attrs.id
      assert user.email == attrs.email
      assert user.role == :admin
      assert user.system_admin == true
    end

    test "parses string role to atom" do
      user = User.from_persistence(%{email: "a@b.com", role: "owner"})
      assert user.role == :owner
    end
  end
end
