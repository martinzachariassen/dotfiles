# Skeletons

Starting points for a **new** README. Fill them only with facts from the
survey, delete what does not apply, and add what the project needs. The
skeleton is a default, not a contract. Anything in `<angle brackets>` is
replaced or removed. None of it may ship as-is.

## PRIVATE

````markdown
# <name>

<One line: what it does, for me.>

## Run

```sh
<the command>
```

## Notes

- <state it was left in / what is half-done>
- <a gotcha that cost time>
````

## PUBLIC

````markdown
# <name>

<One sentence: what it is and the problem it solves.>

[![CI](<workflow badge url>)](<workflow url>) [![License: <SPDX>](<shields url>)](LICENSE)

<Two or three sentences on why it exists and who it is for -- and, if
useful, who it is not for.>

## Install

```sh
<install command>
```

Requires <runtime and version>.

## Quick start

```sh
<smallest command that produces a real result>
```

<What the reader should see.>

## Usage

<The two or three most common tasks, each with a runnable example. Link
`docs/` for the rest.>

## Configuration

| Option | Default | Description |
|---|---|---|
| `<name>` | `<default>` | <what it does> |

## Contributing

Contributions are welcome -- see [CONTRIBUTING.md](CONTRIBUTING.md).
Please report security issues as described in [SECURITY.md](SECURITY.md).

## License

[<SPDX>](LICENSE)
````

## WORK

````markdown
# <name>

<One sentence: what this service or library does for the business.>

**Owner:** <team> · **Channel:** <#channel> · **On-call:** <rotation link>

## Requirements

- <runtime and version>
- <access needed: VPN, cloud role, secrets path>

## Local development

```sh
<setup command>
<run command>
<test command>
```

## Configuration

| Variable | Where the value lives | Purpose |
|---|---|---|
| `<NAME>` | <vault path / parameter store> | <what it controls> |

## Deployment

<Pipeline link, environments, how a change reaches production.>

## Operations

- Dashboards: <link>
- Runbook: <link>
- Architecture / ADRs: <link>
````
