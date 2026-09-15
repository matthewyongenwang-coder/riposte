# Riposte

## Register

Brand. The surface in question is `site/index.html`, a single landing page
deployed to Vercel. The product itself lives on GitHub and runs on your own
machine, so the page's whole job is communication.

## What it is

A fencing video tracker. You film a bout, pick the two fencers once on the first
frame, and it follows them, writes an annotated clip and a CSV of positions and
speeds, and tells you when it has lost one instead of quietly following the wrong
person.

Python and OpenCV. Two pip dependencies, deliberately. It runs entirely offline
with no accounts and nothing uploaded.

It is step one of a larger system: a bout analyzer that keeps a record of
opponents over time, measures tempo and distance habits, gives coaching feedback,
and eventually drives a physical distance and tempo trainer robot. None of that
exists yet, and the page must not claim it does.

## Who it is for

Two readers, and the page has to serve both without splitting in half.

**Fencers, coaches and parents.** Standing in a loud sports hall on a Saturday
morning, or at a laptop that evening. They want to know what happened in a bout.
They are not programmers. The top of the page belongs to them, and it has to look
like something a person can realistically use, not a research demo.

**Reviewers, admissions readers, grant committees.** Judging the engineering.
They are rewarded further down, where the measurements live.

## Brand personality

Honest, measured, practical. The defining trait is that this project publishes
its own failures. Five of ten tracks originally ended on the wrong person, and
that table is on the page. Four separate ideas that did not work are listed with
the numbers that killed them.

That honesty is the entire differentiator and it is also a design constraint: the
page can never sound like marketing, because the substance is the opposite of
marketing.

## Anti-references

- **Generic AI startup landing page.** Gradient hero, three icon cards, fake
  testimonials, a pricing table.
- **Sports analytics corporate.** Stock athletes, navy and neon green, dashboard
  mockups, enterprise language.
- **Research paper.** It has to look usable, not academic.

## Strategic design principles

1. **Show the output, do not describe it.** The imagery is real annotated frames
   from real competitions. A frame of a crowded hall where it is holding the
   correct two fencers argues better than any sentence.
2. **The LOST state is a feature and should be visible.** Most trackers hide
   failure. This one prints it in red. Show that.
3. **Never claim what is not built.** No bout analyzer, no AI coaching, no robot
   on the page until they work.
4. **Structure for what is coming.** The call to action today sends people to
   GitHub to clone it. When the Mac app ships it becomes a download, and when the
   analyzer ships it becomes a second section. Neither should require a redesign.
5. **Every number on the page is one that was measured**, and stays traceable to
   the README.

## Accessibility

Body text at 4.5:1 minimum. The page will be read on a phone in a bright sports
hall, so contrast is a functional requirement, not a checkbox. Full keyboard
navigation, reduced-motion alternative for every animation.
