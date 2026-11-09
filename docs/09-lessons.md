# 9. Lessons

For an AI agent doing this kind of work for a person. The technical lessons
are specific; the procedural ones cost more time than the technical ones
did.

## Technical

**1. The installer never lives on the disk it erases.** Ask of every design:
"if this fails at the worst moment, what can the machine still boot?"

**2. Unattended means one pass.** If the design has a step where a person
runs something, removes something, or types something, it is not
unattended, and that step will be the one that fails. Software, settings and
user data all belong inside the install.

**3. Fail before the point of no return.** Everything the install will need
later (network, download servers) is checked before partitioning. Then
check that the installer cannot quietly undo what you checked: here it could
(docs/05).

**4. An abort setting only helps if its trigger can fire.**
`apt: fallback: abort` looked like a guarantee against erasing the disk
without a network. With no network the installer skips the very check that
triggers it. Read what a safety setting is conditioned on.

**5. Never depend on one server name.** A single hostname was unreachable
from this network for a while when everything else worked. "Online" is "any
of several answers".

**6. Retry what can be slow.** A network that is one second from ready is
not a missing network. One short attempt is a bug.

**7. Validate only what you wrote.** `visudo -c` failed on a file the
distribution ships. Check your own file (`-f`), not the whole system's
state.

**8. Know when the user account exists.** The installer defers user
creation to first boot. Anything for the user's home needs a first-boot
step, ordered before the login screen.

**9. Measure before claiming it fits.** "The Server image fits on the stick"
was said before anyone looked. It was a gigabyte over. Then measure what is
*inside* the thing: the answer was in the breakdown.

**10. Test the assumption the design rests on, in isolation, first.** "apt
will fall back to the network" and "the program's installer works offline"
were each a five-minute experiment. One held, one did not, and the design
changed before any time was spent on it.

**11. The source is on the image. Read it.** Every answer about what the
installer does at a given moment was available in its Python source. The
defect that mattered most was found by reading, not by running.

**12. A test passes for the configuration it ran in, and no other.** Wired
VM runs said nothing about a Wi-Fi-only laptop. List the differences between
the test and the real machine, and for each one either simulate it or read
the code path it changes. Linux can simulate a Wi-Fi card
(`mac80211_hwsim`); use it.

**13. Verify the medium after every change.** Compare the stick with the
build copies, and with the tested image, each time. Record that the real
stick differs from the tested one only by the test hooks.

**14. Fresh state for every run.** New virtual disk, fresh firmware
variables. A run that reuses a half-installed disk tests something else.
Stale installer copies on old partitions broke the very first attempt.

**15. Do not count a helped run as a pass.** Continue a broken run by hand
to find the next bug, by all means. Then fix, and run clean from empty.

**16. Every requirement gets a line in the checklist.** `dmidecode` was on
the "not wanted" list and not in the checklist. It is installed.

**17. Report real-hardware numbers only from real hardware.** 19 minutes in
the VM, 55 on the laptop.

## Procedural

**18. Nothing irreversible without explicit clearance, and clearance is per
action.** Building a stick, running a VM, and erasing the disk are three
different approvals. "Start the test" is not "start the install".

**19. Do not ask yes/no "shall I proceed?" questions.** Say what will happen
and what it costs, do the parts already approved, and stop at the boundary.
When a decision is genuinely the person's, state it as one numbered item
with its consequence.

**20. If the person says it failed, it failed.** An install that produced an
operating system but needed three manual interventions did not meet the
requirement. Arguing the definition wastes their time and yours. Go to the
cause.

**21. No repairs in place.** A system nursed to completion by hand is one
nobody can trust or reproduce. Fix the source, rerun from the start.

**22. Look before asking, and look before proposing.** Check whether the
firmware is already current before suggesting an update. Check what is
plugged in before saying a stick is needed. Check the partitions before
saying space is needed.

**23. Do not add what was not asked for; do not drop what was.** Features
added "helpfully" had to be found and removed. Items silently dropped had to
be found and restored. When something on the list turns out to be
impossible, say so and say why.

**24. Lead with the meaning.** "The installer would have erased the disk and
then failed" before any mention of netplan. The person is deciding whether
to trust the process, not reviewing an implementation.

**25. Do not report what did not happen.** Deleted files, skipped options
and things that are fine are noise.

**26. Answer the question that was asked, then stop.**

**27. When asked "are you sure?", actually check.** The honest answer at
that moment was "not yet", for a reason that could be named: the Wi-Fi path
had never run. Saying "yes" would have cost a wiped disk. The question is
an invitation to find the gap between what was tested and what will run.

**28. Bring bad news immediately and plainly, with the consequence.** The
defect was reported as: what would have happened, why the tests missed it,
what the fix is, how it will be proven. The Wi-Fi card stall was reported
the same way, with the decision left to the person.

**29. Say what the test cannot show.** Three things could only be proven on
the real machine. They were listed before the run. None of them surprised
anyone.
