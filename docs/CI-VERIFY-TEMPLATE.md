# CI receipt verification - drop-in template

> "Verify my claim" as a GitHub Actions line item: other teams pin our
> stdlib-only verifier, point it at their committed `ledger.jsonl`, and their
> CI goes red the day the chain breaks or a scheduled re-check stops matching.

## What it is

`.github/workflows/verify-receipt.yml.example` in this repo. Copy, rename, set
`LEDGER_PATH`. Three properties:

1. **stdlib-only** - the job installs nothing beyond Python; `tamga_verify_mini.py`
   is the same 90-line verifier documented in REPRODUCE (step 2).
2. **pinned, not floating** - the example fetches the verifier from a released
   tag (`v0.2.1`) and prints its sha256 into the job log, so the verifying
   code is itself an audit artifact.
3. **scheduled re-verification** - the weekly cron re-runs the check so the
   green badge in your README carries a *date*. A stale pass reads older,
   not false - the two-field claim from the conformance thread (#3396),
   operationalized.

## Why this matters to us

Every downstream CI that adopts the template becomes an independent,
continuously-running verifier of the receipt format - conformance pressure
without a committee. It is the cheapest possible form of "external node":
their infrastructure, our format, public logs.

## Honest limits

- The template verifies the **chain**, not the *truth* of each receipt -
  garbage-in-garbage-chained. Input binding (`input_sha256`) is how you make
  the inputs arguable.
- The scheduled badge proves the chain was intact at the last run; it does not
  prove the job's outputs were real. Pair with evidence bundles for that.
