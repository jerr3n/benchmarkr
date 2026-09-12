# Reports and history

Benchmarkr keeps recent results in Studio plugin settings and can export results as JSON, CSV, or a
portable RBXM model.

## Recent runs

Every successful run is added to **↶ History**. Benchmarkr retains the 20 newest results. Cancelled
and failed runs do not replace the visible result and are not stored.

History entries are compact reports. They retain:

- exact case summary statistics;
- 48 normalized distribution bins;
- up to 300 representative per-run points, including endpoints and isolated spikes;
- the aggregated profiler tree;
- suite identity, configuration, timer floor, timestamp, and environment metadata.

They do not retain every raw timing sample. Opening an entry displays its saved data without running
the benchmark ModuleScript again.

History belongs to the local Studio installation and is stored with `plugin:SetSetting`. It is not
written into the place or synchronized through Team Create.

## Baselines

Choose **⚑ Pin baseline** after a run to save that report as the baseline for its suite ID. Pinning
again replaces the old baseline.

Cases with the same name are matched. The dashboard reports the current P50 minus baseline P50 and
the percentage change:

- a negative delta is faster;
- a positive delta is slower;
- a case only in the current report is marked as added;
- a case only in the baseline is marked as removed.

Graphs overlay the compact baseline data. Use an explicit `Benchmarkr.Id` so the comparison survives
renaming or moving the ModuleScript. A baseline is evidence, not a performance gate: Studio load,
hardware state, and code outside the suite can still affect a comparison.

## JSON export

**↓ JSON** opens the complete structured report in a selectable dialog. Copy it with Ctrl/Cmd+A and
Ctrl/Cmd+C.

Immediately after a successful run, the JSON includes every raw sample in `cases[].samples`. JSON
exported from history contains the exact summaries and compact graph data but no raw sample arrays.

The current schema version is `1`. Important top-level fields are:

| Field | Contents |
| --- | --- |
| `schemaVersion` | Report compatibility version. |
| `createdAt` | ISO timestamp supplied by Studio. |
| `suite` | Stable ID, display name, and source path. |
| `environment` | Place ID, game ID, and Studio version. |
| `config` | Effective runs, warmups, order setting, and seed. |
| `timerFloor` | Observed `os.clock()` resolution. |
| `cases` | Statistics, graph data, profiler tree, and optional raw samples. |

Consumers should check `schemaVersion` before reading a report and should not assume raw `samples`
are present.

## CSV export

**↓ CSV** opens a spreadsheet-friendly summary with one row per current case. It records counts,
P10/P50/P90, minimum, maximum, mean, and total in seconds. When a baseline is available it also
contains baseline P50, absolute delta, percentage delta, and match status. Removed baseline cases
receive their own rows.

The CSV is a summary, not a raw-sample export.

## RBXM export and import

**↓ RBXM** opens Studio's save-selection dialog. The saved model contains a report folder with:

- a `BenchmarkrReportVersion` attribute;
- a `ChunkCount` attribute;
- ordered `Chunk_00001`, `Chunk_00002`, and subsequent StringValues containing JSON;
- a `SummaryCsv` StringValue.

The JSON is chunked because Roblox Instances have practical property-size limits. Do not rename or
remove chunks.

To reopen a report:

1. insert the exported `.rbxm` into a place;
2. select the report folder in Explorer;
3. open Benchmarkr if it is closed.

Benchmarkr validates the version, chunk count, JSON, and required report fields before display. It
does not execute code from the report folder.

During export, Benchmarkr temporarily creates the report in `ServerStorage` and changes Explorer
selection so Studio can save it. The temporary folder is destroyed and the surviving prior
selection is restored whether the save succeeds or is cancelled.

## Choosing a format

| Need | Format |
| --- | --- |
| Inspect or process all available structured data | JSON |
| Compare summary values in a spreadsheet | CSV |
| Send a report to another Studio user or reopen it later | RBXM |

Studio plugins cannot write arbitrary text files, which is why JSON and CSV use a copy dialog while
RBXM uses Studio's native save-selection flow.
