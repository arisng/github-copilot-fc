# Activation Matrix — machina-authoring

Use this file to tune the `description` field only.

> **Note:** the `Actual Trigger` column contains **reasoned predictions** based on the
> description's trigger phrases, not measured runtime behavior. Every value below is a
> prediction; see each row's Notes for rationale.
<!-- actual-trigger-values-are-predicted-not-measured -->

| ID | Prompt | Should Trigger | Actual Trigger | Failure Type | Notes |
|---|---|---|---|---|---|
| pos-01 | Write a Machina machine JSON for a refund workflow with retry limits. | yes | yes | pass | "Machina machine JSON", workflow modeling — explicit positive phrase |
| pos-02 | Why does my machine score 74? Here is order-fulfillment.json. | yes | yes | pass | "score" + existing machine JSON — matches "explaining why a machine … scores below target" |
| pos-03 | Add retry guards to this state machine JSON so it stops looping forever. | yes | yes | pass | Guard/loop protection authoring — core skill action |
| pos-04 | Generate scenarios for order-fulfillment.json. | yes | yes | pass | "scenarios[]" generation — named in description ("…, scenarios)" |
| pos-05 | Model our signup flow as a Machina state machine in JSON. | yes | yes | pass | Workflow modeling example listed verbatim-ish in description |
| pos-06 | This machine fails validation — fix the JSON so it validates. | yes | yes | pass | Matches "fixing or upgrading an existing machine JSON so it validates" |
| pos-07 | How do I get my machine to score "Excellent"? It's at 85 right now. | yes | yes | pass | Matches compliance-scorer target phrasing ("Excellent" ≥90) |
| pos-08 | What guard syntax does the Machina format support — can I use compare lt on a context key? | yes | yes | pass | Format field/guard semantics question — schema-spec territory |
| pos-09 | Run the compliance scorer on my-machine.json and tell me what gaps remain. | yes | yes | pass | Description now explicitly names "running the bundled machina.py CLI to validate, compliance-score, or generate gaps/scenarios" |
| pos-10 | Upgrade this legacy v1 machine to spec v2.0.0. | yes | yes | pass | "fixing or upgrading an existing machine JSON"; spec v2.0.0 named in description |
| neg-01 | Modify state-machine-simulator.html to improve the graph layout. | no | no | pass | Simulator app modification — explicitly excluded (machina-simulator-maintenance) |
| neg-02 | Build me an XState config in TypeScript for the same workflow. | no | no | pass | XState explicitly excluded |
| neg-03 | Style the compliance modal in the simulator UI. | no | no | pass | Simulator UI — excluded; also styling is out of domain entirely |
| neg-04 | Fix a bug in machina.py's cycle detection algorithm. | no | no | pass | Description now explicitly excludes "debugging or bug-fixing the bundled machina.py scripts themselves" — ambiguity removed |
| neg-05 | Draw a general SVG diagram of my approval flowchart. | no | no | pass | General diagramming explicitly excluded |
| neg-06 | Convert my SCXML document into something the browser can render. | no | no | pass | SCXML documents explicitly excluded |
| neg-07 | Explain how finite state machines work conceptually with examples from embedded systems. | no | no | pass | Conceptual CS education, no artifact authoring — description targets concrete artifacts/actions |
| neg-08 | Update SPEC_REGISTRY in the simulator to add a new spec version. | no | no | pass | SPEC_REGISTRY explicitly excluded |

## Failure type guide

- `false_negative`: the skill should trigger but does not
- `false_positive`: the skill should not trigger but does
- `pass`: behavior matches expectation
