# Public multiplayer via Epic Online Services (EOS)

Goal: **click MULTIPLAYER → QUICK JOIN → you're in a shared server** with
whoever else is online. No IP typing, no port forwarding, no "you need a
friend to host". EOS gives us free anonymous sign-in, lobby matchmaking and
relayed peer-to-peer.

The game already has the whole client side wired (`core/net/EOSBackend.gd`,
the QUICK JOIN button, the lobby → `MultiplayerPeer` → existing sync). It's
dormant until you do the three steps below, because EOS needs a **native
plugin** that only lives in a build you make on your machine — it can't be
compiled or tested in the cloud CI that produces the normal release.

---

## Step 1 — Create a free Epic dev product (≈10 min)

1. Go to <https://dev.epicgames.com/portal>, sign in, accept the Dev Agreement.
2. Create an **Organization** (if you don't have one), then a **Product**.
3. In the product, open **Product Settings**. You'll collect five values:
   - **Product ID**
   - **Sandbox ID** (use the *Live* sandbox)
   - **Deployment ID** (use the *Live* deployment)
   - **Client ID** and **Client Secret** — under **Product Settings → Clients**,
     create a client with a policy that allows the **Connect** and **Lobbies**
     interfaces (the default "Peer2Peer" / "GameClient" policy is fine).
4. Under **Epic Account Services** you do **not** need to configure anything —
   we use anonymous **Device ID** login, so players never sign into an Epic
   account.

Paste the five values into `core/net/EOSConfig.gd`. (They ship inside the
built `.exe` regardless, but don't commit real values to a public repo — keep
the repo private, or fill them only in your local checkout.)

---

## Step 2 — Install the EOS Godot plugin

We target the community GDExtension **epic-online-services-godot**:
<https://github.com/3ddelano/epic-online-services-godot>

1. Download the latest release matching **Godot 4.7**.
2. Copy its `addons/epic-online-services-godot/` folder into the project's
   `addons/` folder.
3. Open the project in the Godot editor once and enable the plugin in
   **Project → Project Settings → Plugins**.
4. Confirm it registered: the editor should now know the `IEOS` singleton and
   the `EOSGMultiplayerPeer` class. (`EOSBackend.plugin_present()` checks
   exactly this.)

The plugin ships the native EOS SDK libraries — that's why this can only run
in a build **you** make, not the headless CI release.

---

## Step 3 — Build the Windows app with EOS

```
godot --headless --export-release "Windows Desktop" StormfighterFlightSim.exe
```

Run it, go **MULTIPLAYER → QUICK JOIN**. The status line walks through:
`Starting EOS → Signing in → Finding a public server → In the server`.

---

## If it doesn't connect first try

`EOSBackend.gd` is written defensively: because it couldn't be tested in the
cloud, every EOS call is guarded and, if the installed plugin names a
method/signal differently than expected, it reports the exact step that
didn't match (e.g. *"connect_interface_login not found"*) instead of hanging.

Send me that status line and the plugin version you installed, and I'll match
`EOSBackend.gd` to your plugin's API — the option dictionaries and callback
signal names are the parts most likely to need a small adjustment.

---

## What already works without any of this

The **ADVANCED — LAN / DIRECT CONNECT** panel (host on this PC / join by IP)
uses the built-in WebSocket transport and needs no plugin or account — good
for same-network play or a port-forwarded host while EOS is being set up.
