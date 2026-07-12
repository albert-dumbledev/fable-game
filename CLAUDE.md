# fable-game

Godot 4.7 first-person survivor-like ("fable-fps"), pure GDScript.

- **Strict typing everywhere** — `untyped_declaration` is an error. Type every `var` and `for` loop, including throwaway test scripts.
- **Verification:** use the `godot-verify` skill (exact engine invocation, harnesses, known false-positives). Don't guess Godot CLI flags or glob for the exe.
- **Content authoring** (aspects, forge nodes, boons, enemies): use the `add-content` skill before touching anything under `data/`.
- **Docs:** one design doc per system in `docs/`; its top status block is that system's changelog of record — update it when shipping, read only the doc relevant to the task.
- Never edit `.gd` files via shell commands (encoding mojibake) — use the Edit/Write tools.
