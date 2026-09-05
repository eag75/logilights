# Security Policy

## Supported versions

Logilights is a small, single-maintainer project. Only the latest release
receives fixes; there are no maintained older branches.

## Reporting a vulnerability

Please report privately, via GitHub's **Report a vulnerability** button
under the Security tab, rather than opening a public issue.

Expect an initial reply within a week. Since this is a spare-time project,
please do not treat that as a service commitment.

## What is worth reporting

Logilights sends USB control transfers to Logitech keyboards and stores a
color per model. Things that would matter:

- A way to make the app write reports to a device it should not touch, or
  with attacker-chosen contents.
- A way to make it load configuration from somewhere other than
  `~/Library/Application Support/Logilights/profile.json`, or to have that
  file's contents cause unsafe behaviour.
- Anything that grants the app, or something using it, more privilege than
  the user running it already has.

## Deliberate design decisions, not vulnerabilities

- **No sandbox.** Raw USB access is incompatible with the App Sandbox, so
  the app is not sandboxed and is not distributed through the App Store.
- **No privilege escalation.** The app never asks for root and holds no TCC
  authorization. Everything it does runs as the logged-in user. If it
  cannot reach a device, it fails rather than escalating.
- **Ad-hoc signing.** Released builds are not signed with an Apple
  Developer ID, because the project has none. Users build the app
  themselves with `scripts/build-app.sh`; no binaries are distributed. A
  downloaded, ad-hoc signed build being rejected by Gatekeeper is the
  expected behaviour, not a bug.
- **Any local process can talk to the keyboard.** macOS does not restrict
  USB control transfers to a device's endpoint 0, so Logilights holds no
  privileged position here and cannot grant or withhold one.
