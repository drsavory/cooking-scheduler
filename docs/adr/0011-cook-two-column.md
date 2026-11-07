# 0011 – Cook screen: actions beside the timeline

**Status:** accepted (amends 0008)

On wide screens (`xl` and up) the cook screen has two columns: a fixed-width, sticky column
on the left with In progress, Up next, Resting, Done and the finish/reset buttons, and the
whole-meal timeline filling the rest. Below `xl` everything stacks with the actions first.

In the timeline, appliances with the same kind and name (for example several "Medium ring"
hobs) share one group header; each dish keeps its own row.

## Amendment: taking out lives on the timer card

"Take out" / "off the heat" is no longer a task in Up next. Each In progress card has its own
button for it (`#out-<dish id>`), so Up next only lists prep and put-in steps. The "Next" time
in the header bar counts down to the next prep or put-in, or to a cooking dish's out time.
