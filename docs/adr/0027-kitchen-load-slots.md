# 0027. Kitchen load slots

- Status: Accepted
- Date: 2026-11-21
- Amends: 0007

## Context

The Kitchen load panel (ADR 0007) drew each oven as a single stacked bar coloured by how full it was.
That showed how busy an oven was, but not which dish was in it, so you had to hover
to find out what was taking up the space.

## Decision

Each appliance in the Kitchen load panel becomes a block of **slots**. Every dish has its
own labelled bar across its time on the heat. A bar's height is the dish's oven space, so a
whole-oven dish fills the full height and a third fills a third. Each dish takes the lowest
space that is free for its whole time: dishes that follow one another reuse the same space,
and dishes that overlap stack up. Other appliances hold one dish, so their bars fill the full
height.

Hob rings of the same size share one row, treated like an oven with a slot per ring
("2 Medium rings"). Each dish sits in the slot of the ring it is actually on, the row says
how many are on at peak ("Up to 1 of 2 on", "All 2 on at peak"), and each free ring shows
as its own dashed box ("Ring free"). Neighbouring free rings are never merged into one box,
and an unused ring row keeps a lane per ring, so 2 rings always look like 2.

- Oven bars show the dish name and its oven space. Hob and other appliance bars use a
  separate tint.
- If the oven is over capacity at any point while a dish is in, that dish's bar turns red
  with a warning icon. Bars that don't fit sit above a dashed "oven full" line. The row label still gives the peak ("Peak 83% full", "Full at peak",
  "Over capacity"). The colour-by-fullness bars are gone.
- Free oven space is drawn as dashed green boxes labelled with how much is free ("1/3 free",
  "Free" for an empty oven), from the start of the panel to serving. That way you can see
  where another dish would fit and when the oven is empty. Ring rows get the same boxes.
  Other appliances don't; their gaps already show it.
- Hovering a bar or focusing it shows the dish, its times and its share of the oven.

`Planner.load/2` adds `slots` to each row, and `Planner.free_space/3` finds the gaps. Both are pure.

Appliances with nothing in them are listed too, in a short faded row that reads "Not used"
with one "Free" box. That way the whole kitchen is visible, and you can see what is spare.
The panel still only appears once at least one dish is placed.

Ovens are listed first, since they are what runs out. Everything else follows in kitchen
order. Unused appliances go below all the busy ones, with ovens still first among them.
