# America Remastered: dedicated server setup

These are instructions for whoever sets the server up, a person or an AI agent with a
shell on the machine. Follow the steps in order. Commands assume a systemd Linux
distribution (Debian, Ubuntu, Fedora, Arch and so on) and a user with `sudo`.

## What this is

Multiplayer runs in lockstep: every player's computer runs the whole game, and only the
players' orders travel over the network. The dedicated server is the meeting point:

- it holds one **lobby** (who plays which people, the map, the settings) and passes every
  order on to the other players;
- it runs **no game**, so it needs none of the original game's assets, no screen and no GPU.
  It uses about 110 MB of memory and almost no CPU;
- the **first player to join leads the lobby**: they pick the map, the seats and the settings,
  and press Start. If they leave, the next player to arrive takes over;
- one process serves **one match at a time**. Players can't join a match that has already
  started. When everyone has left, the lobby opens again;
- it listens on **one UDP port**, 47624 by default. Run more instances on other ports for
  more lobbies.

Players connect from the game's menu: **Multiplayer**, then **Host address** = `server:port`
(the port can be left out if it's 47624), then **Password** if one is set, then **Join**. All
players need the game with its assets, the same game build as each other, and the map the
leader picks.

## Requirements

- Linux on **x86_64** (check with `uname -m`). For ARM, see "Running from source" below.
- systemd, `sudo`, `tar`.
- One free UDP port that the internet can reach (47624 by default).

## 1. Get the package onto the server

The package is `america-server-linux-x86_64.tar.gz`. The game's developer builds it on
their machine with `tools/build_server.sh` and copies it over, for example:

```bash
scp build/america-server-linux-x86_64.tar.gz user@server:~/
```

If you're an agent and can't find the archive on the server, ask the user to copy it.
Don't look for it elsewhere: it isn't published anywhere.

The archive unpacks to `america-server/` with these files:

| File | Purpose |
|---|---|
| `america-remastered.x86_64` | the game program (it also runs as the server) |
| `america-remastered.pck` | the game's scripts (no original assets) |
| `america-server@.service` | systemd unit template; the instance name is the port |
| `SETUP.md` | this file |
| `VERSION` | the commit and network protocol it was built from |

## 2. Install

```bash
sudo useradd --system --home-dir /var/lib/america-server --shell /usr/sbin/nologin america
```

(Skip this if the user `america` already exists. Some distributions keep `nologin` at
`/sbin/nologin`.)

```bash
sudo rm -rf /opt/america-server
sudo tar -C /opt -xzf ~/america-server-linux-x86_64.tar.gz
sudo chown -R root:root /opt/america-server
sudo chmod 755 /opt/america-server/america-remastered.x86_64
```

## 3. Optional: a password

Without a password anyone who finds the address can join the lobby. They can only play
their own seat, but they can take one. To ask for a password on port 47624:

```bash
sudo mkdir -p /etc/america-server
echo 'SERVER_ARGS=--password=CHOOSE_A_WORD' | sudo tee /etc/america-server/47624.env
sudo chown root:america /etc/america-server/47624.env
sudo chmod 640 /etc/america-server/47624.env
```

Use one word with no spaces or quotes, and don't reuse a real password. The game's traffic
isn't encrypted, so this password only keeps strangers out of the lobby.

## 4. Start it with systemd

```bash
sudo cp /opt/america-server/america-server@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now america-server@47624
```

The unit runs the server as the unprivileged `america` user in a sandbox. It restarts the
server if it stops, and starts it at boot.

## 5. Open the port

Inbound **UDP** (not TCP) on the chosen port must be allowed by every firewall in the way.

- ufw: `sudo ufw allow 47624/udp`
- firewalld: `sudo firewall-cmd --permanent --add-port=47624/udp && sudo firewall-cmd --reload`
- plain nftables or iptables: add an accept rule for UDP 47624 in the input chain, in the
  way the machine's existing rules are kept.
- **Cloud providers** (AWS security groups, GCP/Azure firewall rules, Hetzner/OVH/Oracle
  firewalls and so on) filter traffic outside the machine. Allow inbound UDP 47624 there
  too. If you're an agent without access to the provider's console, tell the user exactly
  which rule to add.
- A server at home behind a router needs UDP 47624 forwarded to it.

Check which firewall is active before changing anything (`sudo ufw status`,
`sudo firewall-cmd --state`, `sudo nft list ruleset`). Don't enable a firewall that was off:
doing so over SSH without an SSH rule locks you out.

## 6. Check that it works

```bash
systemctl status america-server@47624 --no-pager
journalctl -u america-server@47624 -n 20 --no-pager
ss -ulpn | grep 47624
```

The log should show `Serving on port 47624 (UDP), protocol 2` (or `..., with a password`).

Then join from the server itself, using the same program as a client for five seconds:

```bash
timeout 5 /opt/america-server/america-remastered.x86_64 --headless -- --join=127.0.0.1:47624 --password=CHOOSE_A_WORD
journalctl -u america-server@47624 -n 5 --no-pager
```

Leave out `--password` if none is set. The client prints a "No asset folder" error; that's
expected, because it isn't going to play. The server's log should show `<name> joined (1 here)`,
then `<name> left` about ten seconds after the client was cut off. If it shows no `joined`
line, the client was refused (wrong password) or never reached the server.

Only a player outside can prove that the port is reachable from the internet. Report back
to the user with:

- the address to type: the server's public IP or DNS name, plus `:port` if it isn't 47624
  (`curl -4 ifconfig.me` shows the public IPv4 address);
- the password, if one was set;
- any firewall rule that still needs adding outside the machine.

## What the log says

`journalctl -u america-server@47624 -f` follows the log live.

| Line | Meaning |
|---|---|
| `Serving on port P (UDP), protocol N` | started and listening |
| `NAME joined (K here)` / `NAME left` | players arriving or leaving the lobby or match |
| `Match started on MAP: ...` | the leader started; the seats and their peoples |
| `Out of sync at step S: {...}` | the players' games have drifted apart (different game builds or maps, or a bug); the match won't stay fair |
| `Player I sent step S after T: put out` | a client sent orders out of order and was disconnected |
| `Match over: the lobby is open again` | everyone left; ready for the next match |

## Updating

The server only needs updating when the network protocol changes: compare `protocol` in
`/opt/america-server/VERSION` with a new package's `VERSION`. Players joining a server with a
different protocol see "The host runs another version of the game". Players still need the
same game build as each other.

```bash
sudo systemctl stop 'america-server@*'
sudo rm -rf /opt/america-server
sudo tar -C /opt -xzf ~/america-server-linux-x86_64.tar.gz
sudo chown -R root:root /opt/america-server
sudo cp /opt/america-server/america-server@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start america-server@47624
```

## More lobbies

Each instance is one lobby. For a second one on port 47625:

```bash
sudo systemctl enable --now america-server@47625
```

Open UDP 47625 the same way as the first port. A password for it goes in
`/etc/america-server/47625.env`. Players join it with `server:47625`.

## Removing it

```bash
sudo systemctl disable --now 'america-server@*'
sudo rm -f /etc/systemd/system/america-server@.service
sudo systemctl daemon-reload
sudo rm -rf /opt/america-server /etc/america-server /var/lib/america-server
sudo userdel america
```

Also remove the firewall rules you added.

## Troubleshooting

- **`Could not open port P`** in the log: another program, or another instance, has that
  port. Check with `ss -ulpn | grep P`.
- **The service keeps restarting**: read `journalctl -u america-server@P -n 50`. Missing
  libraries show as `error while loading shared libraries`; `ldd
  /opt/america-server/america-remastered.x86_64` lists them. The program needs only the
  basic C libraries found on any distribution.
- **Players see "Could not reach the host"**: a firewall or cloud rule is blocking UDP, the
  address is wrong, or the port wasn't forwarded (home servers).
- **"This server asks for a password" / "Wrong password for this server"**: what it says.
- **"A match is being played there"**: wait until it's over, or use another instance.
- **"You don't have the map ..."**: the leader picked a map (for example one made in the
  map editor) that this player doesn't have. Copy the `.ulf` file into their `maps/` folder.

## Without systemd

From the unpacked folder, run this in `tmux`, `screen` or a container:

```bash
./america-remastered.x86_64 --headless -- --dedicated=47624 --password=CHOOSE_A_WORD
```

`--dedicated` with no port uses 47624. In a container, publish the port as UDP
(`-p 47624:47624/udp`).

## Running from source (ARM, or without the package)

This works on any machine where Godot 4.7 runs, given a checkout of the game's repository.

1. Download the Godot **4.7.2** editor for the machine's architecture from
   <https://godotengine.org/download/archive/> (Linux, x86_64 or arm64), unzip it, and put the
   binary on the PATH as `godot`.
2. In the checkout, import the project once: `godot --headless --path game --import`
3. Run: `godot --headless --path game -- --dedicated=47624`

In the systemd unit, set `WorkingDirectory` to the checkout and `ExecStart` to
`/path/to/godot --headless --path /path/to/checkout/game -- --dedicated=%i $SERVER_ARGS`.
The `america` user needs read access to the checkout, and write access to `game/.godot`
(or import as that user).
