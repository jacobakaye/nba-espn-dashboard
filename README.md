# Courtside Data — NBA ESPN read-only game center

A static React website backed by ESPN NBA snapshots collected with R `hoopR` in GitHub Actions. **No predictions or model.**

## Deploy (beginner instructions)

1. Download and unzip the project. Open a terminal inside `nba-espn-dashboard/`.
2. Create a GitHub repository named `nba-espn-dashboard` at https://github.com/new. Set it to **public** if appropriate for your use case. Don't add a README or `.gitignore` through GitHub (already included here).
3. Run:

   ```bash
   git init
   git add .
   git commit -m "Initial NBA game center"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/nba-espn-dashboard.git
   git push -u origin main
   ```

   Replace `YOUR_USERNAME` with your GitHub username. Authenticate with GitHub as prompted.
4. Go to your repository **Actions** tab → **Refresh ESPN NBA data** → **Run workflow**. Leave the date empty to publish yesterday/today/next two days. Watch logs. If the job fails, check the ESPN parsing / dependency messages in the logs.
5. Visit https://dash.cloudflare.com/ → **Workers & Pages** → **Create application** → **Pages** → **Connect to Git** → authorize your GitHub repository. Use the following settings:
   - Production branch: `main`
   - Build command: `npm run build`
   - Build output directory: `dist`
   - Root directory: `/`
6. Deploy. Cloudflare supplies a `*.pages.dev` address. It redeploys when GitHub Actions commits new JSON data.
7. In GitHub repo **Settings → Actions → General → Workflow permissions**, allow **Read and write permissions** if workflow pushes get 403 errors. Organization policies may override this.
8. Check your site and the latest files under `public/data/`. Pick dates with successfully fetched data.

## Local website

Install Node.js 22+, then:

```bash
npm install
npm run dev
```

The site will show that data is unavailable until a successful R update creates date JSON files.

## Local data fetch (optional)

Install R 4.4+ (or a version supported by current hoopR), then:

```r
install.packages(c("hoopR", "jsonlite"))
```

```bash
Rscript scripts/update_data.R
# specific date, if wanted:
NBA_DATE=2026-10-20 Rscript scripts/update_data.R
```

**Important**: Live `hoopR` functions and ESPN endpoints can change and may return empty or missing data. `update_data.R` uses the published `hoopR` wrapper names and cautious schema handling; it has **not been verified against live ESPN in this offline build environment**. Review Actions logs from the first run. All metadata/table columns are displayed from the returned data; no predictive statistics are created.

## What the collector currently includes

- Schedule from `espn_nba_scoreboard()` (daily)
- League standings and league injuries from `espn_nba_standings()` and `espn_nba_injuries()` (today)
- Per-event broadcasts, odds, and officials
- Both teams' season stats, schedule, roster, injuries and leaders when ESPN team IDs are present
- Box scores when game status indicates in progress or final

**Not included by default:** per-player game logs, every one of hoopR's 105 wrappers, play-by-play, and depth charts. Those can be added as optional follow-on collectors after the core pipeline is validated, since blindly fetching every player for every game would create substantial request load.

## Troubleshooting

- **No date file:** Open the Actions job log. See whether `espn_nba_scoreboard` failed or scoreboard parsing failed.
- **Unknown team IDs:** The ESPN scoreboard schema may differ from the known patterns in `scripts/update_data.R`. Inspect `names(hoopR::espn_nba_scoreboard(...))` and expand the `as_game()` mapping as needed.
- **Empty tables:** ESPN may return genuinely empty data, a temporary error, or an unsupported season. The site labels these rather than creating values.
- **Access denied during git push:** Set GitHub Actions workflow permissions as described above.
- **Cloudflare deploy fails:** Confirm Node runtime is 22+ and build/output are `npm run build` / `dist`.
- **No live data on the site:** The build may have finished before the R data workflow. Re-run the data workflow, then check that Cloudflare deployed its commit.

## Provenance and rights

Data comes from ESPN via the community-maintained hoopR package. This project is not affiliated with ESPN or NBA. Review rights and terms before publicly redistributing ESPN data, odds, logos or photos.
