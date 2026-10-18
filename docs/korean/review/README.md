# Translation review records

[Open the approved review bundle](index.html). The current catalog is
`e1a3ccaa468b`; `current.json` identifies its full catalog and bundle hashes.
The [approval receipt](../../../assets/korean/approval.json) pins every file in
that snapshot, so its contents stay unchanged. Its historical `draft` labels
record the state when review was requested; the separate receipt records the
subsequent approval.

The approved bundle contains the original/translated text, source references,
glossary, editorial decisions and 105 offline font/layout previews. These
previews helped review the translation; [native game screenshots](../screenshots/README.md)
show the implemented result.

The superseded `9e0e64e13dc2` and `401ad4dca31d` snapshots are preserved in
`history.tar.xz`, with exact file hashes and version identities in `history.json`.
They are useful for tracing earlier wording, but are not inputs to the current
approved build.

```sh
python3 -m tools.korean.evidence check
python3 -m tools.korean.evidence extract --archive review-history --output build/review-history
```

`make korean-review` preserves an existing snapshot and updates the current
entry point. A changed translation version requires a new review and approval;
editing a frozen bundle invalidates its hashes.
