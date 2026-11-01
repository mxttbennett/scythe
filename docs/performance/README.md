# Performance KPIs

`ScytheBench` times the work behind each interaction that can feel slow, on a fixed
synthetic history of 4,633 entries (about two years of a heavy user's time, generated from a
fixed seed so every run does the same work). Run it in release, as the app ships:

```sh
make bench                                  # table, compared with the pre-optimisation baseline
swift run -c release --package-path Packages/ScytheCore ScytheBench --json out.json
swift run -c release --package-path Packages/ScytheCore ScytheBench --only analytics --seconds 10
```

Each KPI reports the median of 7 to 30 runs after 3 warm-up runs. A **budget** marks where it
turns visible: 8 ms for work on the main thread (one frame at 120 Hz) and 100 ms or more for
background work a person waits on. `baseline.json` is the build before the optimisation pass;
`after.json` is the run in the table below (Apple M5, macOS 27).

## Results

| KPI | Thread | Budget (ms) | Before (ms) | After (ms) | Speedup | Status |
|---|---|---:|---:|---:|---:|---|
| Read history.json from disk and decode it (`startup.history-load`) | background | 100 | 45.55 | 45.26 | 1.0× | ok |
| Encode and write history.json after an edit (`startup.history-save`) | background | 100 | 61.24 | 48.82 | 1.3× | ok |
| Fetch and decode a full two-year backfill (`sync.harvest-decode`) | background | 200 | 168 | 108 | 1.6× | ok |
| Merge a full backfill into an empty history (`sync.history-cold-merge`) | background | 100 | 2.15 | 2.19 | 1.0× | ok |
| Incremental refresh: 15 edits plus the 60-day window (`sync.history-refresh`) | background | 100 | 3.27 | 2.29 | 1.4× | ok |
| Fold the menu bar's day back into the history (`sync.history-absorb`) | main | 8.00 | 1.12 | 0.067 | 17× | ok |
| Build the search index after any change (`explorer.index-build`) | background | 100 | 7.69 | 6.12 | 1.3× | ok |
| Filter by text with the search index (`explorer.search-text`) | background | 8.00 | 10.43 | 0.895 | 12× | ok |
| Filter by period, three projects and billable (`explorer.filter-facets`) | background | 8.00 | 0.020 | 0.019 | 1.1× | ok |
| Rebuild the filter menus after any change (`explorer.facets`) | main | 8.00 | 0.993 | 0.686 | 1.4× | ok |
| Sort the table by a text column (`explorer.sort-text-column`) | background | 8.00 | 135 | 1.24 | 109× | ok |
| Sort the table by date, newest first (`explorer.sort-date-column`) | background | 8.00 | 3.05 | 0.332 | 9.2× | ok |
| Export every entry as CSV (`explorer.csv-export`) | main | 100 | 26.66 | 13.95 | 1.9× | ok |
| Draw the Analytics tab over every entry (`analytics.open-all`) | main | 8.00 | 40.72 | 2.81 | 15× | ok |
| Redraw Analytics after typing a search (`analytics.open-filtered`) | main | 8.00 | 20.65 | 3.74 | 5.5× | ok |
| Build a week's timesheet from the history (`timesheet.build-week`) | main | 8.00 | 0.176 | 0.081 | 2.2× | ok |
| Resolve all ten period presets (`dates.presets`) | main | 8.00 | 0.023 | 0.0005 | 43× | ok |
| Add days to a date and measure the gap (per 1,000) (`dates.arithmetic`) | main | 8.00 | 6.90 | 0.081 | 85× | ok |
| Filter the project picker as you type (`targets.search`) | main | 8.00 | 0.697 | 0.350 | 2.0× | ok |
| Group picker rows by project (`targets.group`) | main | 8.00 | 0.067 | 0.069 | 1.0× | ok |

Four KPIs were over budget before and none is now. The geometric mean speedup across all
twenty, including the ones left alone, is 4.1×.

## At launch

The history model is built with the status item, so whatever it does in `init` is main-thread
time before the menu bar item can respond. It used to decode `history.json` there.
`StartupPerformanceTests` measures it with a 5,000-entry file (Debug build, since the app
tests only build in Debug):

| KPI | Before | After |
|---|---:|---:|
| Main thread blocked by `HistoryModel.init` (ms) | 61 | 0.06 to 0.35 |

## What changed

- **Sorting a text column** (`EntrySort`): `KeyPathComparator` ran a locale-aware compare on every
  one of about 60,000 comparisons. Each distinct text is now ranked once and rows are ordered by
  integer. The order is identical, checked against `KeyPathComparator` on accents, widths and numbers.
- **Analytics** (`EntryAnalytics`): the weekend test went through `Calendar` for every entry, several
  times over, and groupings built a string key per entry. It is now one pass with arithmetic dates.
  The Analytics tab also filtered without the search index, on the main thread.
- **Text search** (`SearchIndex`): searches folded bytes with `memmem` instead of walking `Character`s,
  folds plain ASCII without calling Foundation, and folds each distinct string once.
- **Date math** (`CalendarDate`): Gregorian calendars skip `Calendar` for `adding`, `daysSince` and
  `startOfWeek`. Other calendars take the old path.
- **Launch** (`HistoryModel`): the cache file is read off the main thread. A refresh waits for it, so
  it still updates what was saved instead of starting over.
- **Absorbing the menu bar's day** (`EntryHistory`): a handful of entries are looked for one by one
  instead of indexing the whole history.
- **Harvest decode**: a snake-case key strategy and a timestamp parser for the one format Harvest
  sends, each checked against Foundation's own.

## Left alone

`history.json` still takes about 45 ms to decode and 48 ms to encode. Both run off the main thread
now. Most of that is `Codable` itself, so a real gain means changing the file format, which is a
decision for its own change.
