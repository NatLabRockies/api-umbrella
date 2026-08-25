# Architecture

API Umbrella is a reverse proxy that sits between your API users and your APIs:

![](../images/overview.svg)

## In More Detail

### Components

![](../images/router.svg)

### Gatekeeper

![](../images/gatekeeper.svg)

## Agent Evaluation and Scoring Loop

For internal automation workflows, API Umbrella follows a repeatable evaluation loop:

1. Assign a clear target.
2. Execute work against that target.
3. Collect measurable evidence from the outcome.
4. Grade performance against the target.
5. Update agent value, asset value, and reputation from the grade.
6. Adjust responsibility and mentorship scope.
7. Repeat with re-evaluation, adaptation, and optimization.

The invariant is:

`target → perform → evidence → grade → learn → responsibility change → repeat`

This loop is designed to keep decisions measurable, feedback-driven, and continuously improving over repeated iterations.
