defmodule Cadence.Reads.Notifications.InboxTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts
  alias Cadence.Accounts.{OrganizationInvitationRow, User, UserRow}
  alias Cadence.Applications.{HostContext, OrganizationAdminQuery, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Notifications
  alias Cadence.Notifications.{Actions, Notification, NotificationRow}
  alias Cadence.Organizations.Organization
  alias Cadence.Reads.Notifications.Inbox

  setup do
    user = user!()
    %{user: user, scope: %Scope{actor_kind: :user, user: user}}
  end

  test "an account without organization membership pages all its own notifications with binary ties",
       c do
    at = ~U[2026-09-01 00:00:00.000000Z]

    ids = [
      "notif-a",
      "notif-A" | Enum.map(1..51, &"notif-#{String.pad_leading(to_string(&1), 3, "0")}")
    ]

    Enum.each(ids, fn id ->
      n = notification!(c.user, notification_id: id)

      Repo.get!(NotificationRow, n.notification_id)
      |> Ecto.Changeset.change(inserted_at: at)
      |> Repo.update!()
    end)

    foreign = notification!(user!())
    assert Accounts.list_user_memberships(c.user.user_id) == []
    assert {:ok, first} = Inbox.load(c.scope, %{})
    assert length(first["notifications"]) == 50

    assert {:ok, second} =
             Inbox.load(c.scope, %{
               "before_at" => first["next_cursor"]["at"],
               "before_id" => first["next_cursor"]["id"]
             })

    assert length(second["notifications"]) == 3
    assert second["next_cursor"] == nil

    assert Enum.map(first["notifications"] ++ second["notifications"], & &1["id"]) ==
             Enum.sort(ids, :desc)

    refute Enum.any?(
             first["notifications"] ++ second["notifications"],
             &(&1["id"] == foreign.notification_id)
           )

    refute Map.has_key?(first, "total_count")

    assert {:ok, _} =
             Actions.execute(c.scope, "mark_notification_read", %{"notification_id" => hd(ids)})

    assert {:ok, unread} = Inbox.load(c.scope, %{"unread" => "true"})
    refute Enum.any?(unread["notifications"], &(&1["id"] == hd(ids)))
  end

  test "read invitation state remains pending until the authoritative acceptance creates membership",
       c do
    {invitation, notification, org} = invite!(c.user)

    assert {:ok, %{status: "read"}} =
             Actions.execute(c.scope, "mark_notification_read", %{
               "notification_id" => notification.notification_id
             })

    assert {:ok, before} = Inbox.load(c.scope, %{})
    assert [row] = before["notifications"]
    assert row["read_at"] != nil
    assert row["invitation_status"] == "pending"

    probe =
      Path.expand(
        "../../../../../../frontend/apps/host/src/auth-and-navigation/features/notifications/producer-consumer-probe.mjs",
        __DIR__
      )

    {output, status} = System.cmd("node", [probe, Jason.encode!(before)], stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "NOTIFICATIONS_CONSUMER_OK"
    refute Map.has_key?(row, "metadata")
    refute Map.has_key?(row, "action_url")
    refute Map.has_key?(row, "token_digest")

    assert {:ok, %{status: "accepted", navigate: "/"}} =
             Actions.execute(c.scope, "accept_invitation", %{
               "notification_id" => notification.notification_id
             })

    assert {:ok, membership} = Accounts.fetch_user_membership(c.user.user_id, org.organization_id)
    assert membership.lifecycle_state == :active

    assert Repo.get!(OrganizationInvitationRow, invitation.organization_invitation_id).status ==
             "accepted"

    assert {:ok, after_acceptance} = Inbox.load(c.scope, %{})
    assert hd(after_acceptance["notifications"])["invitation_status"] == "accepted"

    Repo.get!(UserRow, c.user.user_id)
    |> UserRow.update_changeset(%{
      email: "changed-#{System.unique_integer([:positive])}@example.com"
    })
    |> Repo.update!()

    assert {:ok, after_email_change} = Inbox.load(c.scope, %{})
    assert hd(after_email_change["notifications"])["invitation_status"] == "accepted"

    assert {:error, :invitation_not_pending} =
             Actions.execute(c.scope, "accept_invitation", %{
               "notification_id" => notification.notification_id
             })
  end

  test "expired, revoked, foreign-email and missing invitations cannot advertise pending acceptance",
       c do
    {invitation, notification, _} = invite!(c.user)
    row = Repo.get!(OrganizationInvitationRow, invitation.organization_invitation_id)

    for {attrs, expected} <- [
          {%{expires_at: DateTime.add(DateTime.utc_now(), -1)}, "expired"},
          {%{status: "revoked"}, "revoked"},
          {%{email: "another@example.com"}, "unavailable"}
        ] do
      Repo.get!(OrganizationInvitationRow, row.organization_invitation_id)
      |> Ecto.Changeset.change(attrs)
      |> Repo.update!()

      assert {:ok, doc} = Inbox.load(c.scope, %{})
      assert hd(doc["notifications"])["invitation_status"] == expected

      assert {:error, _} =
               Actions.execute(c.scope, "accept_invitation", %{
                 "notification_id" => notification.notification_id
               })
    end

    missing =
      notification!(c.user,
        kind: :organization_invitation,
        metadata: %{"organization_invitation_id" => "missing"}
      )

    assert {:ok, doc} = Inbox.load(c.scope, %{})

    assert Enum.find(doc["notifications"], &(&1["id"] == missing.notification_id))[
             "invitation_status"
           ] == "unavailable"
  end

  test "fresh active recipient authorization denies foreign IDs, stale disabled users and malformed inputs",
       c do
    other = notification!(user!())
    own = notification!(c.user)

    assert {:error, _} =
             Actions.execute(c.scope, "mark_notification_read", %{
               "notification_id" => other.notification_id
             })

    assert {:ok, untouched} = Notifications.fetch_notification(other.notification_id)
    assert untouched.read_at == nil

    for query <- [
          %{"unread" => "false"},
          %{"before_at" => "invalid", "before_id" => "id"},
          %{"before_id" => "id"},
          %{"user_id" => "foreign"},
          %{"unread" => %{}}
        ] do
      assert {:error, _} = Inbox.load(c.scope, query)
    end

    for input <- [
          %{},
          %{"notification_id" => own.notification_id, "user_id" => c.user.user_id},
          %{"notification_id" => %{}}
        ] do
      assert {:error, _} = Actions.execute(c.scope, "mark_notification_read", input)
    end

    for scope <- [nil, %Scope{}, %{c.scope | actor_kind: :service}] do
      assert {:error, _} = Inbox.load(scope, %{})

      assert {:error, _} =
               Actions.execute(scope, "mark_notification_read", %{
                 "notification_id" => own.notification_id
               })
    end

    Repo.get!(UserRow, c.user.user_id)
    |> UserRow.update_changeset(%{lifecycle_state: "disabled"})
    |> Repo.update!()

    assert {:error, _} = Inbox.load(c.scope, %{})

    assert {:error, _} =
             Actions.execute(c.scope, "mark_notification_read", %{
               "notification_id" => own.notification_id
             })

    assert {:ok, untouched} = Notifications.fetch_notification(own.notification_id)
    assert untouched.read_at == nil
  end

  test "the federated bell produces bounded recipient evidence for its actual host owner", c do
    other = user!()
    foreign = notification!(other)
    own = for index <- 1..7, do: notification!(c.user, title: "Notice #{index}")
    read = List.last(own)

    assert {:ok, marked} =
             Notifications.mark_notification_read(read.notification_id, c.user.user_id)

    query = %SurfaceQueryRequest{
      application_key: "organization_admin",
      application_version: 1,
      surface_id: "notifications_bell",
      surface_version: 1,
      query_id: "cadence.organization.notifications_bell",
      query_version: 1,
      params: %{}
    }

    assert {:ok, %{"data" => %{context: context}}} =
             OrganizationAdminQuery.load(
               c.scope,
               HostContext.user(c.user.user_id),
               query
             )

    assert context.version == 1
    assert context.user.user_id == c.user.user_id
    assert context.unread_count == 6
    assert length(context.notifications) == 5

    assert Enum.any?(
             context.notifications,
             &(&1.notification_id == read.notification_id &&
                 &1.read_at == DateTime.to_iso8601(marked.read_at))
           )

    refute Enum.any?(context.notifications, &(&1.notification_id == foreign.notification_id))

    assert {:error, _} =
             OrganizationAdminQuery.load(
               c.scope,
               HostContext.user(other.user_id),
               query
             )

    probe =
      Path.expand(
        "../../../../../../frontend/apps/host/src/auth-and-navigation/features/notifications/federated-bell-probe.mjs",
        __DIR__
      )

    {output, status} =
      System.cmd(
        "node",
        [probe, Jason.encode!(%{context: context, expectedUserId: c.user.user_id})],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "FEDERATED_BELL_CONSUMER_OK"
    assert Notifications.count_unread_notifications(c.user.user_id) == 6
  end

  defp user! do
    user =
      User.new(%{
        email: "inbox-#{System.unique_integer([:positive])}@example.com",
        display_name: "Inbox Recipient",
        confirmed_at: DateTime.utc_now()
      })

    Repo.insert!(UserRow.changeset(user))
    user
  end

  defp notification!(user, opts \\ []) do
    n =
      Notification.new(
        Map.merge(
          %{
            user_id: user.user_id,
            kind: :organization_access_granted,
            title: "Account access",
            body: "A notification",
            metadata: %{}
          },
          Map.new(opts)
        )
      )

    {:ok, persisted} = Notifications.persist_notification(n)
    persisted
  end

  defp invite!(user) do
    org =
      Organization.new(%{
        display_name: "Invited Organization",
        slug: "inbox-#{System.unique_integer([:positive])}"
      })

    {:ok, org} = Cadence.Organizations.persist_organization(org)

    {:ok, %{invitation: invitation}} =
      Accounts.establish_organization_access(user.email, org.organization_id,
        force_invitation: true,
        invited_by_user_id: user.user_id
      )

    [notification] = Notifications.list_notifications(user.user_id)
    {invitation, notification, org}
  end
end
