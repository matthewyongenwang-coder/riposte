# Riposte design system

## The scene

A parent in a bright, loud sports hall on a Saturday morning with a phone in one
hand, and a coach at a laptop that evening looking at the same bout. Both want to
know what happened. Neither wants to read a paper.

## Theme: dark, and for a reason

The hall is bright and the footage is bright. Fencers wear white kit under
fluorescent light. Every real image on this page is a near-white photograph, so
the page is a dark frame around bright evidence, the way a gallery wall is dark
so the work is not.

Dark here is gallery logic, not developer-tool logic. It is a cool near-black,
not a warm charcoal and not a terminal green-on-black.

## Color: committed, and inherited from the product

The palette is not a design choice, it is the tracker's own semantics. Orange is
Fencer A, blue is Fencer B, red is LOST. Those three colors appear in every
annotated frame the program has ever written, so the page and the output share
one language.

```
--bg        oklch(0.155 0.008 260)   near-black, faint cool cast
--surface   oklch(0.205 0.010 260)   raised panels, table rows
--line      oklch(0.290 0.012 260)   hairlines and borders
--ink       oklch(0.965 0.004 260)   headings and body
--muted     oklch(0.740 0.012 260)   secondary text, 4.5:1 on --bg
--a         oklch(0.760 0.170 55)    Fencer A, orange. Primary accent.
--b         oklch(0.700 0.140 250)   Fencer B, blue. Secondary.
--lost      oklch(0.650 0.210 25)    LOST. Used only for failure.
--ok        oklch(0.760 0.150 155)   a measured improvement
```

Strategy is Committed: orange carries the page. Red is rationed and never
decorative, because on this page red means a real failure and using it for
ornament would be lying.

## Type

Two families, one voice.

**Archivo** for everything structural. A grotesque built for high-performance
printing and signage, which is what the physical reference is: the number bib on
a piste, the scoreboard above it, equipment labelling. The variable width axis
carries the display sizes, so there is no second display face competing.

**JetBrains Mono** for measurements, commands and anything the program printed.
Numbers on this page are evidence, and they should look like readouts.

Scale is fluid `clamp()` with a 1.3 ratio between steps. Display max is 5.5rem,
letter-spacing floor -0.035em. Light-on-dark gets +0.06 line-height.

## Layout

Full-bleed imagery, because the images are the argument. Content column caps at
68ch for prose and widens for tables. Spacing is fluid and deliberately uneven:
generous between sections, tight inside a measured claim and its number.

No card grid for the mechanism section. Those five items are a pipeline with
different weights, not five equal features, and an equal grid would flatten that.

## Motion

One orchestrated entrance on the hero, then per-section reveals that suit what
they reveal: tables fill row by row because they are being read, images fade
because they are being looked at. Content is visible by default and the reveal
enhances it, so a headless renderer or a background tab still ships the page.

Every animation has a `prefers-reduced-motion` crossfade alternative.

## Structure, and what changes later

The page is built so the next two milestones drop in without a redesign.

1. **Hero action slot.** Today it is "Get it on GitHub" plus "How to film".
   When the Mac app ships it becomes "Download for Mac" with the GitHub link
   demoted to secondary. Same component, same position.
2. **Roadmap section.** Holds what is coming, clearly marked as not built. When
   the bout analyzer ships, that entry graduates into a full section above the
   measurements and the roadmap keeps the rest.

## Rules

- No claim on this page that is not measured and traceable to the README.
- Red is only ever failure.
- Every number is set in mono.
- No em dashes anywhere.
