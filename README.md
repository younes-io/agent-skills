# younes-io/agent-skills

A portable Agent Skills repo for TLA+ workbenches, with a generated Claude Code plugin wrapper.

## Skills

- `tla-check`: Write and iteratively refine executable TLA+ specs (`.tla`) and TLC configs (`.cfg`), run TLC model checking, and summarize counterexamples.
- `tla-proof`: Write and iteratively refine TLAPS theorem proofs in TLA+ (`.tla`), run `tlapm`, and summarize proved vs failed/omitted obligations.

## Install / List (Portable Agent Skills)

List skills from this repo (local checkout):

```bash
npx -y skills add . --list
```

Install from GitHub:

```bash
npx -y skills add younes-io/agent-skills --skill tla-check
npx -y skills add younes-io/agent-skills --skill tla-proof
```

Alternatively, use the URL form:

```bash
npx -y skills add https://github.com/younes-io/agent-skills.git --skill tla-check
npx -y skills add https://github.com/younes-io/agent-skills.git --skill tla-proof
```

## Claude Code Install

Add the marketplace in Claude Code:

```text
/plugin marketplace add younes-io/agent-skills
```

Install the plugin:

```text
/plugin install tla-workbenches@younes-agent-skills
```

Reload plugins:

```text
/reload-plugins
```

Invoke the plugin-qualified skills:

```text
/tla-workbenches:tla-check
/tla-workbenches:tla-proof
```

## Repo layout

Skills live under:

- `skills/<skill-name>/SKILL.md`
- `skills/<skill-name>/agents/`
- `skills/<skill-name>/scripts/`
- `skills/<skill-name>/references/`

Claude-specific wrapper files live under:

- `.claude-plugin/marketplace.json`
- `plugins/tla-workbenches/.claude-plugin/plugin.json`
- `plugins/tla-workbenches/skills/`
- `scripts/sync_claude_plugin_skills.sh`
- `scripts/validate_claude_plugin.sh`

The root `skills/` directory is the only editable source of skill content. The Claude plugin `skills/` tree is generated from it and committed for GitHub-based Claude Code installs.

## tla-check prerequisites

See `skills/tla-check/SKILL.md` for full usage.

Examples: <https://github.com/younes-io/tlaplus-workbench-examples>

Common prerequisites:
- `bash`
- `jq`
- `java`
- `tla2tools.jar` (set `TLA2TOOLS_JAR` or pass `--jar` to the runner script)

## tla-proof prerequisites

See `skills/tla-proof/SKILL.md` for full usage.

Examples: <https://github.com/younes-io/tlaplus-workbench-examples>


Common prerequisites:
- `bash`
- `jq`
- `tlapm` (or pass `--tlapm` with an absolute path/wrapper)
