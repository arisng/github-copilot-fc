## Language

**Episode**: One run of a single skill inside a chat — a slice of the transcript, not the whole transcript.
_Avoid_: full session, the whole chat, recording

**Session**: The complete transcript of one chat with the AI — every message, click, and command, saved as a list of events.
_Avoid_: recording, transcript window, run

**Telemetry**: The durable artifact one audit writes — the dated report — stored in the target skill's `telemetry/` folder (legacy name: `benchmarks/`; *benchmark* is reserved for waza's authored evals).
_Avoid_: benchmark report, baseline file

**Deterministic step**: A tool step that ran pre-authored code — a repo script, build, test, or other command nobody wrote on the spot.
_Avoid_: automated score, good step

**Semantic step**: A tool step where the model authored or judged content — writing, editing, or deciding rather than executing something pre-written.
_Avoid_: AI step, manual step

**Boundary row**: A line in an episode report showing a helper skill's load that was merged into the owning skill's measurement, with that helper's own token and step totals.
_Avoid_: merged load, sub-window attribution

**Tool step**: One completed tool call inside an episode — a command run, a file edited, or a file read.
_Avoid_: operation, click
