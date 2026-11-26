# Dev mailbox: accepting an invitation from a seed (#745)

A new account exists only by accepting an invitation, and the token reaches the invitee only by
email. No product API returns it (the invite responses carry no token). In dev the mailer is
Swoosh's in-memory `Local` adapter, and the dev build mounts `Plug.Swoosh.MailboxPreview` at
`/dev/mailbox` (HTML) and `/dev/mailbox/json`. Test and prod builds do not route it
(`config :cadence_web, :dev_routes` is set only in `dev.exs`; a test covers this).

A seed that works as a REST client does what a person does:

1. A person with the right role invites the address: `POST /api/v1/organizations/:id/invitations`
   (or the admin route), signed in through `POST /api/v1/auth/sign-in`.
2. Read the email: `GET /dev/mailbox/json`, take the newest message to that address and the
   `/invitations/<token>` link in its body.
3. Accept with a password: `POST /api/v1/auth/invitations/<token>/accept`.

The mailbox is per dev server process and is cleared when it restarts.
