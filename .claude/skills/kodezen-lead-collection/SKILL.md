---
name: kodezen-lead-collection
description: Collects Kodezen sales leads (small local businesses with a bad, non-responsive website) for a given city, neighborhood, Google Maps keyword, business type and directory, then writes them into the user's own tab of a shared Google Sheet. Uses Claude in Chrome. Use when the user says "lead collect", "lead khuj", "lead sheet", "bad design site", "non-responsive site lead", or gives a row from the research sheet (city, neighborhoods, maps keywords, business type, directory sites, Kodezen offer).
---

# Kodezen lead collection

Goal: find small local businesses whose website looks very bad (old or ugly, basic functionality works, often NOT responsive) and fit a Kodezen product. Write each lead into the user's own tab of the shared Lead Submission Sheet.

## 0. Inputs to get first

### Where the keywords come from (research sheet, read-only, never edit)
- Sheet: **Data Research & Formula Sheets**, tab **Person & Work**
  `https://docs.google.com/spreadsheets/d/17Ni-YsMubV5t1k6bG39s5NOWsxS39ZtB-8GJaszdPaE/edit?gid=1635818872`
- Each person has one row; column A = person name (the user's name, e.g. "Abu Abdullah"). Columns: B City, C Neighborhoods, D Maps keywords, E Business type, F Directory sites, G Kodezen offer, H Good signals (what a good lead looks like), I Skip (what to avoid). Cells hold one item per line.
- Open it in Chrome, find the user's row, and read the cells (scroll right to see all columns; cells are tall, so scroll down and take screenshots, `get_page_text` does not read the grid). Do not change anything in this sheet.
- Use the FIRST neighborhood, FIRST Maps keyword, FIRST business type and FIRST directory site (Houzz, Yelp, Angi, etc.) unless the user says otherwise; the user's current assignment was "first neighborhood + first keyword + first business type + first 5 directory sites -> 5 leads". Then widen to the next neighborhood / keyword when candidates run out.
- Use column G for the Kodezen products to pitch, column H as extra quality signals and column I as a skip list (for example big chains, franchises).
- If the user gives a different row or keyword in chat, the chat overrides the sheet.

### Where leads are written (lead sheet)
- Sheet: **Lead Submission Sheet**
  `https://docs.google.com/spreadsheets/d/1uuTnjOvlEmi_rrZTqlFMBQTVXZn7GOSPo9sMeNQ9X8k/edit?gid=<tab gid>`
- Write ONLY in the tab named after the user (for example "MD Abu Abdullah", gid 1675465824). There is one tab per team member; never edit the others.
- Start at the first empty row under the header, below any existing leads. Do not delete or overwrite existing leads unless the user explicitly says so.

### Other inputs
- How many leads (default 5).
- How many leads (default 5).
- Rules: edit ONLY the user's own tab. Never touch other tabs or other people's rows. Never delete data unless told ("delete kore replace" was explicitly approved once; ask again).

## 1. Hard rules learned (user corrections)
- The user wants sites that look **very bad** visually. Good, polished, modern designs are rejected, even if WordPress. A moderately plain site is NOT enough.
- Best leads: bad look + basic functionality + **not responsive**. Platform does not matter (WordPress, Wix, Duda, custom all OK). WordPress is a bonus only.
- Check the **full site visually** (home, 2-3 inner pages, contact form), not just the first screen.
- Never write "not found / not linked / none" in the Social Link column. List only real links.
- Every link in a cell must be a full `https://...` URL and the whole URL must be one clickable link (see section 5).
- Lead should have real traction: ideally 20+ Google reviews, an owner who replies, real address and phone or email. Say it plainly when review count is small.
- Do not guess data. Every field must come from the site, Google Maps or a directory.
- Do not add Claude/AI mentions anywhere.

## 2. Finding candidates
1. Google Maps search: `https://www.google.com/maps/search/<keyword>+<city or neighborhood>+TX`.
2. Extract website URLs of the results with JS (strip query strings, otherwise the tool blocks the output):
```js
const f=document.querySelector('div[role=feed]'); if(f){for(let i=0;i<5;i++){f.scrollTo(0,99999); await new Promise(r=>setTimeout(r,1500));}}
JSON.stringify([...document.querySelectorAll('a[aria-label^="Visit"]')].map(a=>{let h=a.href; if(h.includes('/aclk')) return null; return a.getAttribute('aria-label').replace(/^Visit /,'').replace(/.s website$/,'')+' | '+h.split('?')[0]}).filter(Boolean))
```
3. Also use Houzz and the directory sites from the research row. Vary keywords, neighboring cities (Arlington, Keller, Southlake, Burleson, Mansfield, Haltom City, Benbrook, Weatherford...) and categories (remodeler, handyman, builder, architect, interior designer, cabinets, tile, flooring).
4. Skip: national chains, franchises, huge firms (a $3B civil contractor is not a lead), sites behind Cloudflare/captcha, and sites that do not load.

## 3. Screening (do this BEFORE reading a site in detail)
Automatic responsive test. On the site's own page, load the same page in a 390 px iframe and compare scroll width:
```js
const vp=(document.querySelector('meta[name=viewport]')||{}).content||null;
const ifr=document.createElement('iframe');
ifr.style.cssText='position:fixed;left:0;top:0;width:390px;height:700px;opacity:0;pointer-events:none;border:0';
ifr.src=location.pathname||'/'; (document.body||document.documentElement).appendChild(ifr);
await new Promise(r=>{ifr.onload=r; setTimeout(r,6000)}); await new Promise(r=>setTimeout(r,1000));
let m={}; try{const d=ifr.contentWindow.document.documentElement; m={sw:d.scrollWidth,cw:d.clientWidth}}catch(e){m={err:String(e)}}
ifr.remove(); JSON.stringify({u:location.host,vp:!!vp,m})
```
- `sw > cw` (e.g. 980 or 1558 vs 390) = not responsive = strong candidate.
- `sw == 390` = responsive: only continue if the design is truly ugly.
- Run one site per `navigate` + JS pair; a cross-domain redirect breaks the JS (just retry on the final URL). Batch several sites in one `browser_batch`.
- The browser window cannot go below about 619 px, and there is no device mode. For a visual phone view, replace the page body with an iframe of width 390 (and 820 for tablet) and take screenshots, scrolling the iframe with `contentWindow.scrollTo`.
- Tablet check: window or iframe at 820 px. A fixed ~980 px layout also overflows at 820.
- Animated reveals make text look overlapped or faint for a moment. Wait 3-4 seconds after scrolling and screenshot again before calling something a bug.
- `screenshot` can be denied for some domains. If so, say so and skip, do not claim a visual check.

## 4. Visual review of a candidate
Take screenshots (scale 0.5-0.6) at the top, then scroll 8, 10, 15 ticks; open at least the contact page, a service or project page. Note concrete problems only:
- clashing colors/textures, tiny or low-contrast text, huge empty gaps, text over busy photos, tiny logo or no logo, cropped hero, pinned header covering content
- stock photos instead of real work, no gallery or before/after, long keyword text walls, inconsistent brand names
- bare or broken contact form, no phone or email, no map
- images without alt text (count with JS), icons linking to the network home pages
- mobile (390) and tablet (820) behavior, page height, sideways scroll
Collect from the page with JS: `tel:` and `mailto:` links, social links (facebook, instagram, houzz, linkedin, youtube, yelp, bbb), nav items, address, technology (generator meta, `wp-content`, `wixstatic`, `cdn-website` = Duda, `squarespace`, `Divi`, etc.). Strip query strings in the output.
Then open the business in Google Maps (`get_page_text`): rating, review count, address, phone, owner replies, review themes.

## 5. Writing into the Google Sheet (reliable method)
Read the current header row first. The sheet structure changes between sessions (columns were inserted, removed and renamed by teammates). Use the structure that exists NOW. Last seen structure (A-K):
A Business Name, B Website name, C Email / Phone, D Phone (optional), E Sent (leave empty), F Technology, G Social Link, H Website Problem, I Your offer, J WordPress (Y/N dropdown), K Notes.

Rules that avoided bugs:
- Window size changes move the name box. Take a screenshot first and click the real name box (about x=40, y=103-104 in a 1562-wide frame). If you type without focusing it, keystrokes can land in other cells or trigger Sheets shortcuts (a stray `/` opens search). Verify with a zoom that the name box shows the target cell before typing.
- Select a cell with the name box (`ctrl+a`, type `A6`, Enter). Press Enter once to enter edit mode, then type. Typing directly onto a selected cell can drop the first character (a leading bullet).
- Use Tab to move right inside a row. Press Tab twice to skip the Sent column.
- Newline inside a cell: type the line, `wait 1 s`, then `alt+Return`. Without the wait, newlines are randomly lost.
- Bullet format: `• text`, one point per line, in Website Problem, Your offer, Social Link and Notes.
- Links: type the full `https://...` URL followed by a **trailing space**, then `alt+Return` (or Return on the last line). Without the trailing space only the part up to the first `.com` becomes a link. Verify by opening the cell: each URL must be a single link.
- WordPress dropdown: type `Y` or `N`, then Enter.
- Do not start a cell with `+` or `=` (Sheets treats it as a formula). Write `Phone: +1 ...`.
- After writing a row, select `A<row>:K<row>` and set vertical align to Top (toolbar align menu, first icon).
- Clipboard tricks (`execCommand('copy')`, `navigator.clipboard`) do not work here and can freeze the tab.
- After navigating or reloading, version history panels stay open; press F5 to close them. If a row looks blank it may be a scroll rendering issue; check version history before assuming data was lost.

## 6. Content of each lead
- **Business Name / Website name**: as on Maps and the domain only.
- **Email / Phone**: only what is publicly listed. Put both when available. If none: `Email: not listed on the site` is acceptable here (this is a contact field, not social).
- **Technology**: Wix, Duda, WordPress (theme), Squarespace, custom. Add "fixed ~980 px layout, not responsive" when true.
- **Social Link**: real links only, each a full URL: Facebook, Instagram, Houzz, BBB, LinkedIn, WhatsApp, Google Maps search URL with `(4.9 stars, 46 reviews)`.
- **Website Problem**: 6-9 specific, verified bullets. Always include responsive findings (390 px and 820 px), contact/form problems, missing gallery, alt text count.
- **Your offer**: bullets per Kodezen product with the reason it fits (ECM portfolio, GemBoards project tracking, aBlocks clean sections, GemBooking for estimates), one `Offer:` line and one `Why it fits:` line. Do not pitch a booking tool if they already have online scheduling.
- **WordPress (Y/N)**: dropdown.
- **Notes**: Maps rating, address, niche, owner name only if shown, services, service area, hours, who built the site (footer credit), how it was found, and whether it is outside the planned neighborhood list.

## 7. Workflow per lead
1. Pick candidate, run the responsive screen, visually review, collect contact and Maps data.
2. Show the user the evidence if unsure; otherwise write the row.
3. After each lead, give a short prompt for another Claude session to collect the remaining leads in parallel, starting at the next free row, then continue with the next lead yourself (the user asked for this).
4. Close tabs you opened when done. Report: what was written, what was rejected and why, and any assumption.

## 8. Reject list examples (do not re-check)
Polished modern sites are rejected even if WordPress (Haus of Blaylock, Landry Designs, Salvation Home Remodeling, Make Ready Home, Darnell Green). Non-responsive but huge (North Texas Contracting) or premium looking (Lee's Remodeling) were kept only as backups.
