# younes-io/skills

A small skill pack compatible with the Vercel `skills` CLI.

## Skills

- `tlaplus-workbench`: Write and iteratively refine executable TLA+ specs (`.tla`) and TLC configs (`.cfg`), run TLC model checking, and summarize counterexamples.

## Install / List (Vercel skills CLI)

List skills from this repo (local checkout):

```bash
npx -y skills add . --list
```

Install from GitHub:

```bash
npx -y skills add younes-io/skills --skill tlaplus-workbench
```

Alternatively, use the URL form:

```bash
npx -y skills add https://github.com/younes-io/skills.git --skill tlaplus-workbench
```

## Repo layout

Skills live under:

- `skills/<skill-name>/SKILL.md`
- `skills/<skill-name>/agents/`
- `skills/<skill-name>/scripts/`
- `skills/<skill-name>/references/`

## tlaplus-workbench prerequisites

See `skills/tlaplus-workbench/SKILL.md` for full usage.

Common prerequisites:
- `python3`
- `java`
- `tla2tools.jar` (set `TLA2TOOLS_JAR` or pass `--jar` to the runner script)

