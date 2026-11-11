# AI Prompt Log

**Tool used:** Claude (Anthropic)

------------------------------------------------------------------------

## 1. Understanding the assignment before writing code

**My prompt:** \> "do not do anything yet just read and understand the project"

**What happened:** The AI summarized the project as a pipeline (import → filter → categories → join → spatial join → geography comparison → reviewer adjustment) and flagged risks before any coding: the review file's memory size, keeping raw data off GitHub, and that the New Orleans neighborhood layers come from the City, not `tigris`.

**Why it mattered:** Starting with a plan meant I set up `.gitignore` for `data/raw/` *before* any data existed, so the 5 GB files never risked being committed.

## 2. Planning the large-data import around my computer

**My prompt:** I sent a screenshot of *About This Mac* (24 GB RAM, 765 GB free disk).

**What happened:** The AI pointed out that disk space wasn't the constraint, memory was: loading the full 5.3 GB review file with text could need 15–25 GB of RAM. It suggested streaming the file in chunks with `stream_in(handler = ...)`, keeping only New Orleans reviews from each chunk.

**Result:** All 6,990,280 reviews were scanned in 2.5 minutes with peak memory around 1.3 GB, and no sampling. This became the core of my large-data management section.

## 3. Fixing an error: `print(n = 30)` on a data frame

**My prompt:** I pasted the error: \> `Error in print.default(m, ...) : invalid 'na.print' specification`

**What happened:** The AI explained that `stream_in()` returns a plain `data.frame`, not a tibble, and `print(n = ...)` only works on tibbles. The fix was adding `as_tibble()` right after import.

**Lesson:** The professor's template code assumed a tibble; checking the object's class solved it.

## 4. The city filter: don't trust exact matching

**My prompt:** I pasted the table of all city spellings containing "orleans."

**What happened:** The output showed `NEW ORLEANS`, `New orleans`, and `new orleans` alongside `New Orleans`. The template's `city == "New Orleans"` would have silently dropped those. We switched to `str_to_lower(str_squish(city)) == "new orleans"`.

## 5. Re-prompting on the maps (several rounds)

My maps took several rounds of fixes, each driven by me sending a screenshot back:

| What I saw | What was wrong | Fix |
|------------------------|------------------------|------------------------|
| Map title cut off | Title too long for the plot width | Shortened the title |
| Every area except one looked the same pale color | One neighborhood had 164 restaurants, so a linear color scale flattened everything else | Log color scale with clear breaks |
| The census tract map was black when I viewed it | `theme_void()` draws no background, so the PNG was transparent | `ggsave(..., bg = "white")` |
| The zoom the AI added didn't zoom | The `coord_sf()` limits weren't applied as expected | Removed the zoom; the full-city view turned out to be more honest anyway |

**Lesson:** I could only catch these by actually looking at every saved figure, not just trusting that the code ran.

## 6. Catching an bug: `NA` values in a summary column

**My prompt:** I pasted the neighborhood table. Several neighborhoods showed `NA` in `pct_above_norm`, including the French Quarter, which has 118 rankable restaurants.

**What happened:** The AI found bug: restaurants with no eligible reviewers had `NA` counts, and indexing with `[count >= 20]` pulled those `NA`s in, turning the whole mean into `NA`. The fix was adding `!is.na(...) &` to the condition. It also explained that `NaN` for neighborhoods with zero rankable restaurants is correct.

## 7. My most important re-prompt: questioning the "best neighborhood"

The AI first recommended **Leonidas–West Carrollton** as the best neighborhood, even though **Tulane–Gravier** had the highest adjusted score. I pushed back:

> "since Tulane–Gravier is the best NSA why not Tulane–Gravier we choose Leonidas–West Carrollton instead"

**What happened:** The AI admitted that Tulane–Gravier passed the rule we had set (at least 5 rankable restaurants), so choosing Leonidas could look like moving the goalposts after seeing the results. Instead of arguing, it proposed a test: **recompute each neighborhood's score without its single best restaurant**, and decide *before* looking at the result:

| Neighborhood             | Adjusted score | Without its best restaurant |
|--------------------------|---------------:|----------------------------:|
| Tulane–Gravier           |          0.315 |                       0.186 |
| Leonidas–West Carrollton |          0.207 |                       0.203 |

Tulane–Gravier's lead depended on Avery's On Tulane, which supplied about a third of its eligible reviews. Leonidas barely changed. The conclusion stayed the same, but now it rests on evidence instead of a judgment call. The leave-one-out check is in the final report.

------------------------------------------------------------------------

## What I learned about working with AI

- **Question recommendations, especially convenient ones.** My Tulane–Gravier question produced the strongest analysis in the project.
- **Check the AI's claims against the data.** Even the AI's own summary contained a factual error that only a check against the table caught.
- **Ask for predictions before running code.** Predicting results first (for example, how many reviewers wrote only one review) helped me notice when something looked off.
