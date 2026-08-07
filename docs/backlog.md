# Improvement backlog

Live queue for this camera. Ordered by value per unit of risk, not by how
interesting the problem is.

**Rules that earned their place** (2026-08-06, the day most of this was found):

- **Read the artifact before measuring the device.** Every conclusion drawn from
  disassembly, source or `/proc` held. Nearly every conclusion drawn from an
  unvalidated measurement was overturned.
- **This firmware narrates itself.** Twice the answer was a log line nobody had
  read — `[ak_drv_ir_set_ircut:229] not inited` and `## ASLC OPEN OK ena:1`.
  Run the binary in the foreground and read its output before inferring anything.
- **Establish what depends on a fault before repairing it.** Three separate bugs
  turned out to be the only reason something worked.
- **Verify the effect, not the invocation.** A `200`, an exit code and a
  `DrwAck` all mean *parsed*, not *honoured*.
- **Prefer the SD card to the squashfs root.** Card edits are recoverable by
  pulling the card. Root edits are not.
- **When you learn something, grep for every place that says otherwise.** A doc
  gets edited where the new fact lands, not where the old one lives — so it ends
  up carrying a claim and its own refutation, paragraphs apart, both reading
  authoritative. Three instances in one day: `troubleshooting.md` stating a
  green-fraction IN band of 1.06–1.39 while `ptz.md` recorded two confirmed IN
  readings that band scores as misses; a `SPK_PA must be high before each run`
  precondition that is 0 before *every* run by design, because the player raises
  it itself; and `usr-sbin/README.md` calling `/sbin/updater` "not yet analysed"
  four paragraphs above the section analysing it. **The stale half is the
  dangerous half**, because it reads like the checked one.

  **A fourth instance closed the distance to two lines**, and that is the part
  worth keeping. `identity.md` claimed *"a raw seed caps at 32 distinct names
  however many cameras you own"* directly beneath a table whose own
  `random MACs | 256 | 229` row disproves it. Nobody spotted it — not the
  author, not two reviewers — until an adversarial read went looking. So
  **proximity is not protection**: a refutation one line away is no more likely
  to be noticed than one in another file, because nobody re-reads the paragraph
  they just wrote. The measured table was right and the sentence summarising it
  was wrong, which is the usual direction — **prose drifts, data doesn't.**
  Trust the table; re-derive the sentence.

  > **The mechanism, found 2026-08-06 by the person it happened to** — worth
  > having, because the rule above describes the phenomenon without explaining it:
  > **writing something down discharges the feeling of having handled it.**
  >
  > `nebula-inventory` documented a measurement trap (ffmpeg's `time=` is the
  > *media* timestamp, so frames ÷ time is a declared number wearing a
  > measurement's clothes) — **and then failed to apply it to the sentence three
  > paragraphs above**, which used exactly that artifact as evidence. In its
  > words: *"I didn't fail to know the rule — I documented it, and didn't apply it
  > upward. The trap warning read as **complete** to me because it was
  > **correct**."*
  >
  > It had propagated three ways before an outside read caught it: into the
  > footnote, into the test script built *after* writing the warning, and into the
  > assumption that the test would answer the question the warning invalidated.
  > **One reading of a diff surfaced all three.**
  >
  > 🔑 **So the remedy is not "re-read harder".** Your own re-reads are least
  > reliable on exactly the text you just wrote, and correctness makes it worse
  > rather than better — a passage that is *right* feels finished. **The only
  > mechanism that works is someone else reading it**, which is why review is
  > cheap here and self-review is close to worthless.

  (True version, for the record: the cap is **per aligned 256-wide MAC window**,
  because the noun index is bits 8–12 and those are constant inside one. It is
  not a global ceiling.)

  **The same failure also runs at FILE scale, and that is why the rule above did
  not catch it.** An audit on 2026-08-06 found five live contradictions with one
  shared cause: **today's findings landed in this backlog, and the reference docs
  were never revisited.** The volume ladder, the ASLC result, the OTA analysis and
  the identity rationale were all correct *here* while `ptz.md`, `web-ui.md`,
  `home-assistant.md` and `hardware.md` still said what they said that morning.

  The existing rule says to grep for contradictions when you learn something — and
  it failed because the sweep looks *near* the new fact, and the contradiction was
  in a different file with a different reader. **Nobody greps their own working
  notes.**

  > **The backlog is what we read. The reference docs are what a stranger reads.**
  > A doc set can be **collectively correct and individually misleading**, and the
  > stranger gets the wrong answer every time.

  So: **when a finding lands here, it is not documented — it is queued.** Landing
  it means editing the page a stranger would open.

- **When a file contains both a table and a summary sentence, re-derive the
  sentence.** Three of the four worst rows in that audit were a table refuting its
  own prose — the `identity.md` cap above, `hardware.md` calling `/etc/jffs2` "the
  only writable place that persists to flash" one line above a mount table listing
  `/data` as `jffs2 rw`, and a green-fraction band contradicted by the readings
  beside it. At that frequency it is not bad luck, it is **the dominant mode**.
  Tables are usually dumps — measured. Summaries are usually unsourced and drift.

- **Printing evidence and requiring interpretation is not a guard.** It fails
  precisely when the operator is in a hurry, which is when destructive tools get
  run. `write-sd-card.sh` printed a full `lsblk` listing before its ERASE prompt
  — the right design, and not enough. On 2026-08-06 the only removable device
  present was **JP's bootable Multitool card**, and it passed every check the
  tool had: `removable=1`, not the system disk, backup present. **Two different
  people reached that prompt within thirty minutes of each other**, both at the
  end of a long session, both told to "write a card and call it done".

  The fix was to **refuse by default** — a camera card is blank or a single FAT32
  partition, anything else needs `--force-wipe` — and to name what was found
  rather than list it: `MULTITOOL`, and the mountpoints, not "3 partitions".

  > **A guard should convert "an operator interprets output" into "a human
  > answers a direct question about a named thing."**

  It worked the first time it fired: the refusal was taken to JP rather than
  overridden, he cleared it explicitly, and *then* the flag was used.

  🔑 **And the escape hatch must be documented with the refusal.** A user who hits
  a refusal, does not know an override exists, and reaches for `dd` instead **has
  been made less safe by a guard working correctly.** An undocumented override is
  not extra safety; it is a detour into a tool with no guard at all.

- **A correction is trusted more than the original — so a wrong correction costs
  more than the error it replaced.** On 2026-08-06 a firmware doc said *"196 KB
  before `KERNEL`, none of it inside a named partition."* **True.** One piece of
  contradicting evidence turned up — `erase_env=sf erase 0x20000 0x2000`, an
  address below `KERNEL` — and the layout was rewritten around it, with a
  prominent ⚠️ admitting the earlier "over-claim". **The admission was the
  error.** `MAC` and `ENV` sit at `0x1B1000`/`0x1B2000`, *after* the kernel.
  Reading the bytes at `0x20000` settles it in seconds: u-boot code and strings
  (`Check read OK`), no environment anywhere near it.

  **The evidence was real; the reading of what it pointed at was not.** And the
  failure mode is specific: *finding something that contradicts your claim is
  not the same as finding your claim wrong.* The other possibility — that the
  new evidence means something else — never got tested, because a correction
  feels like rigour and rigour feels like a stopping point.

  > **The tell: correcting a claim without measuring the thing the new evidence
  > supposedly shows.** `erase_env` was read; `0x20000` was not.

  Why it is worse than the original: a page that says *"this used to say X, and
  X was wrong"* has spent its credibility on the new statement. The next reader
  does not re-derive a claim that has already survived one correction — and
  everything downstream of it (here, a whole risk analysis about a redundant
  environment pair) inherits the mistake with confidence attached.

  **Same-day companion:** the redundancy argument built on that anchor was
  refuted too. Both collapsed the moment someone dumped the address instead of
  reasoning about it.

- **The repo is not the world. "No evidence here" is not "it never happened."**
  On 2026-08-06 a firmware write-up stated *"nobody has had a serial console on
  one of JP's cameras"* and gated a whole plan on the cost of getting one —
  soldering to bare pads located from another board revision's photos. **JP had
  had UART on his own camera all along**; it is how the hack was worked out, and
  he uses a pogo clip, so the real cost was *unscrew and clip*.

  The reasoning was sound right up to the last step. Every UART artifact in
  `reference/` genuinely is from a different revision — so *"this repo holds no
  evidence of a console on JP's units"* was **true**. It was then written down as
  a claim about the world, and the search scope silently became the system scope.

  > **The tell: a sentence about what nobody has done, sourced entirely from
  > what you have read.** A repo records what someone chose to commit; JP's own
  > bench work was never going to be in it.

  Cheap remedy, and it is what actually worked here: **state the absence as an
  absence, and address it to whoever would know.** *"I can find no record of UART
  on these units — has anyone had a console on one?"* costs one sentence and
  invites the correction. The assertive version invites agreement instead. JP
  volunteered the answer within minutes of being told what we believed —
  **because we told him what we believed.**

- **"What does this do?" and "does this actually run?" are different questions,
  and code answers only the first — very convincingly.** A script or function is
  self-contained and legible: reading it gives you a complete, correct, confident
  account of its behaviour, with real filenames, real defaults and real addresses
  you can put in a table. **What it cannot tell you is whether its preconditions
  hold, because what defeats it is outside the text.**

  **The tell, every time, was checking a dependency rather than following the
  logic.** Four instances on 2026-08-06, all in this firmware:

  | Reads as | Actually |
  |---|---|
  | `/usr/sbin/wifi_ap.sh` — a complete soft-AP: SSID fallback `AKIPC_XXX`, open network, camera at `192.168.0.1`, `udhcpd` for DHCP | **Nothing calls it, and the `hostapd` it invokes is not on the filesystem.** Confirmed dead by a live 90-second scan |
  | `camera_set_ircut()` — a function that writes a GPIO. It does | …then **hardcodes `return 0`**, so every caller sees success whether or not the write landed. *The logic is correct; the reporting is a lie* |
  | `libre_anyka_app`'s day/night thread — working IR-cut control | writes `/sys/user-gpio/gpio-ircut_a`, **a path this kernel does not expose**. `ENOENT`, silently, forever |
  | `update.sh`'s md5 verification — integrity checking. It is | …inside `if [ -e <file>.md5 ]`. **Omit the `.md5` and no verification happens**, and the flash proceeds |

  **Before reporting what a code path does, establish that it runs:** does
  anything call it, do the files it names exist, does anyone check what it
  returns.

  > 🔑 **This is the boundary condition on ["read the artifact before measuring
  > the device"](#improvement-backlog), which is why it belongs near the top.**
  > That rule held four-for-four today and is still right. But **reading the
  > artifact tells you *intent*, not *liveness*** — and intent is the more
  > persuasive of the two, because it arrives with detail.
  >
  > The near-miss is the argument: `lucid-camera` had the SSID, the IP, the
  > interface and the DHCP server ready to hand JP. **All accurate. All describing
  > code that cannot execute.** A reader would have gone looking for a network
  > that does not exist.

  Two smaller ones in the same family — **a source that reads authoritative and
  answers a different question than the one you asked:**

  * **A binary's `--help` is documentation, and documentation lies.** BusyBox's
    `ftpd` in this build prints *"Anonymous FTP server"* and lists no auth flag.
    **It authenticates.** Reported as-read that becomes *"every stock camera
    offers unauthenticated root file-write"* — false, alarming, and the kind of
    claim that gets repeated. Only a probe caught it.
  * **`grep -rl` gave an incomplete answer that looked complete.** Searching
    `/usr/sbin` for `Factory` returned only `camera.sh`; a direct single-file
    grep found the real referrer in `service.sh`. **When a recursive search
    underpins a structural conclusion, spot-check one file you *expect* to
    match** — a search that silently under-reports is indistinguishable from a
    system that genuinely lacks the thing.

  Full context for all six in
  [`docs/stock-attack-surface.md`](stock-attack-surface.md) (`ad81d5d`).

- **A sweep built from what you expect to find will miss what you didn't expect to
  be there.** A real address survived four separate scrubs on 2026-08-06 because
  every sweep was assembled from a mental model of where addresses live, and the
  file was a new directory added mid-session. It was caught by a mechanical pass
  that **extracted every token of an identifier shape and printed the distinct
  values to classify**, rather than grepping for known-bad ones.
  **Enumerate from the artifact, not from memory.** Second instance the same day:
  "there are two paths to the speaker" when there were eight.

  Corollary that falls out of it: **sort such a list by frequency and read the
  bottom first.** A value appearing once is the one no convention covers.

  > ⚠️ **The binaries under `scratch/anyka-white-led/` carry real identifiers** —
  > `mtdblock3-env-baseline.bin` holds an `ethaddr`, and `mtdblock5.bin` is a whole
  > rootfs image. They are scratch, not repo, **and must stay that way.** If either
  > is ever promoted, it needs *reading* first, not copying. A binary is the one
  > artifact a text sweep cannot classify for you.

- **Transcription is where verified evidence degrades — in both directions.**
  Both failures happen at the same step, moving a measurement into a document,
  and neither is caught by "go and check" because **the checking already
  happened.** Two instances, 2026-08-06, same day, opposite signs:

  **Dropped the detail that *was* the evidence.** `web-ui.md`'s port table
  recorded `tcpsvd 0 21 ftpd -w /` under a heading stating it was verified with
  `netstat`. The live invocation is `… -w / -t 600`, and **`-t 600` comes from the
  stock `rc.local` and from nothing the hack does** — so the one flag identifying
  the process as the *vendor's* was the one lost in transcription. That omission
  is why two pages said `run_ftp=1` *starts* FTP, when it only stops `run_ftp=0`
  from killing it.

  **Kept the detail that should not have travelled.** A measured `stats` payload,
  handed over as a contract, contained JP's **real SSID and a real AP BSSID** —
  caught in review before it reached a public repo.

  > 🔑 **Why the second one is a different animal from every other identifier
  > miss here.** The others were **someone typing a value into prose** — an act of
  > authorship with a moment where you could choose otherwise. **A measured payload
  > has no such moment: you run a command, paste the output, and the output is the
  > point.** Editing it feels like weakening the evidence.
  >
  > **The property that makes a verbatim payload good documentation is the property
  > that smuggles the data.** It is trusted *because* it is unedited, and
  > **evidence is the thing we are least inclined to edit.**

  **Two remedies, one per direction:**

  * **Sanitise at the point of *capture*, not the point of writing.** Substitute
    `<SSID>` in the script that prints the sample, where it is a deliberate act —
    not in the document, where it competes with fidelity and loses.
  * **When copying a verified command line, copy it whole.** If you shorten it,
    you are deciding which arguments carry no information, and on this firmware
    that judgement has already been wrong once.

- **Before a repo's first push, a leak must be AMENDED OUT, not fixed forward.
  A fix-forward publishes the thing you are fixing.** This is the single window in
  a repository's life where history is free to rewrite — no clone exists, no
  force-push is needed, nobody's work is at risk — and it closes the instant you
  push.

  Happened twice on 2026-08-06, and the second time is the instructive one: a
  pre-publication scrub **found the leak**, fixed it in a follow-up commit, and
  then pushed the whole history. The scrub worked. The disposal did not.

  > **It is the only condition under which "the tree is clean, the history is not,
  > accept it" is avoidable at zero cost** — and it is spent by the most natural
  > motion available, which is to commit a fix.

  ⚠️ **This rule has a placement problem worth stating inside it:** it only helps
  someone *before* their first push, which is exactly when nobody is reading a
  backlog. **If you are creating a repo, the check belongs in that repo's own
  README or CLAUDE.md, not only here.**

- **When a decision is made *because* of a condition, write the condition next to
  it.** *"Drop the history sweep — moot"* was correct when made and rested
  entirely on those repos staying private. They were published three hours later
  and **nothing re-examined the decision**, because nothing recorded what it
  depended on.

  Four words would have carried it: **`moot — they're local`**. Then a later
  reader sees the premise, and sees when it expires.

  > **The premise moved because of the deciding party's own later action** — not
  > an external change. That is the harder case: you will not notice your own
  > move invalidating your own earlier reasoning, because from the inside it is
  > just the next thing you did.

  Same instinct as writing a disposal condition on a note: **a note that states
  what would make it wrong is doing work the whole time it sits there**, and can
  be retired by anyone rather than only by its author.

- **A fix whose evidence is an *absence* needs a way to observe the behaviour** —
  or the next person re-reports the bug. (Anyka volume, 2026-08-06; cost a false
  *"still broken"* verdict within the hour.) Two halves:

  **(a) Duplicated correct implementations are camouflage for the missing one.**
  Two call sites handled volume and one did not — an asymmetry a reader could
  spot. Centralising removed the bug *and* the only visible clue it had ever
  existed.

  **(b) Ship an observation with it.** `anyka_http.py level` answers *"is it
  wired up?"* in one command, where a code read cannot. **Put the reason in the
  new code's comment**, or someone deletes it as redundant.

  Applies to any invisible-by-design fix: a removed workaround, a defaulted config
  key, an inherited behaviour. **If the diff is mostly deletions, ask what a
  reviewer is meant to point at — and if the answer is "nothing", build the thing
  they can.**

  > **The compounding is the part that generalises.** After centralising, all three
  > call sites look identical, so **the correct state and the defect are
  > byte-identical from a code read** — only behaviour distinguishes them. The
  > false verdict came from checking for the *old shape* and finding none. That is
  > the same failure as ["proximity is not protection"](#improvement-backlog) seen
  > from the reviewer's side: **the reader is looking where the evidence used to
  > be, and a good fix is precisely what moves it.**

- **Fix where the repository is the only authority; report where reality is.**
  The test: **can this fix be wrong about the world?** If no — a broken anchor, a
  renamed heading, a stale path, a typo — fix it. If yes — a number, a mechanism,
  a version, a threshold, a recommendation, *"how X behaves"* — **it is a claim,
  whatever it looks like**, and the repo is a *record* of it rather than the
  source. Correcting one means asserting something about hardware nobody
  re-measured, which is how most of the retractions above happened.

  **Prefer this test to "trivial vs substantive".** That one is a judgement call
  every time and therefore erodes under pressure; *who is the authority* returns
  the same answer regardless of who is asking or how tired they are.

  > ⚠️ **A doc contradicting another doc is NOT mechanical, however obvious the
  > newer one looks.** **Neither doc is the authority**, so choosing between them
  > is an assertion about the device wearing a tidy-up's clothes — and it has
  > already been wrong here: the most *evidenced* source was the least *current*,
  > and the resolution came from a human, not from the files.

- **A surprising first sample is a sample, not a finding — and the more
  interesting it is, the more samples it owes you.** The rule below covers a
  *uniform* result meaning a broken instrument. This is the opposite shape and
  the more seductive one, because **a surprise feels like a discovery rather than
  an error**, and nothing about it prompts you to repeat the measurement.

  2026-08-06: the first `/vs0` frame-rate sample came back at **14.76 fps,
  behind real time** — the exact anomaly someone had said to watch for. It was
  nearly written up. **Five more samples clustered at 15.15–15.81. The 14.76 was
  noise.**

  > **The recursion is why this earns a rule rather than a note.** Publishing it
  > would have **replaced one wrong conclusion drawn from n=1 with a different
  > wrong conclusion drawn from n=1 — on the same page, within the hour, while
  > writing the commit message about why n=1 was the problem.** A rule that can be
  > violated in the act of documenting it is one worth writing down.

  ⚠️ **And the half that helps whoever is *briefing* the measurement, not taking
  it: telling someone in advance which result would be interesting biases what
  they do with the first one.** The *"if it comes back lower you've found
  something more interesting"* framing was **mine**, handed over before any
  sample existed — which converted a noisy first reading into a pre-confirmed
  hypothesis the moment it arrived. The person measuring caught it by taking five
  more; **I would have read the write-up and believed it, because I would have
  been reading my own prediction back.**

  **Say what you want measured. Do not say which answer would be exciting.**

- **A uniform result across varied inputs means a broken instrument, not a
  conclusion.** Six different `&level=` values that all report the same thing are
  telling you about your *test*, not the system. Seen four times today: a `ps`
  parse that showed all six volume variants as the same binary; six snapshot
  frames returning luma `130.47` to two decimals because the server was serving
  one cached frame; `ctl` returning `OK` for every command whether honoured or
  not; and `camera_set_ircut` hardcoding `return 0`. **Before believing a null or
  a uniform result, feed the instrument an input you already know differs** — if
  it cannot tell those apart, it cannot tell anything apart.
  **Two of those four are in vendor code, and that is why they survived for
  years**: the reporting layer and the thing being reported were written by the
  same people, so nothing in the system ever disagreed with itself. A firmware
  that always says `OK` is internally consistent and externally useless. Expect
  the vendor's own success signals to be decorative until proven otherwise.

- **Re-verifying the axis that burned you last time is not verification.** A
  check adopted after one failure becomes a *ritual*, and performing it discharges
  the feeling of having verified — while the axis that decides *this* case goes
  unasked, precisely because the verification step is already ticked.

  2026-08-06, twice in one afternoon, on the same rule:

  | | |
  |---|---|
  | First miss | reported a broken anchor that had been **fixed four commits earlier** — did not re-check *existence* |
  | Adopted | *"re-verify immediately before reporting"* |
  | Second miss | re-checked existence dutifully — **and never asked whether the leak was published**, which was the whole decision |
  | Adopted | *"check existence **and** publication"* |
  | Third miss | checked both, correctly — then reported **the wrong actor had fixed it**, having verified only that the state changed |

  **The third one is the worst, because the check was already known to be
  impossible.** Every agent here commits as `jp`, which
  [this project had already written down](#improvement-backlog) — so *"who made
  this change"* is **not answerable from git at all** and has to come from a
  person. Knowing that, the claim was still made, because the change appeared in
  that session's repo and the inference felt like it needed no work.

  > **Verifying that a state changed is not verifying who changed it**, and a
  > false attribution is worse than a missing one: it reads later as evidence that
  > cross-session coordination happened when nobody relayed anything.

  The second report said *"not in history only — in the current tree"*, drawing a
  contrast **between two things, one of which had not been looked at.** The repo
  had **32 unpushed commits**: the leak was in the tree and *not yet public*,
  which is the [free window](#improvement-backlog) where a leak can be **amended
  out** instead of accepted. Reported as though already public, that option
  disappears.

  > 🔑 **This is [*"writing it down discharges the feeling of having handled
  > it"*](#improvement-backlog) one layer up — applied to verification instead of
  > documentation.** A correct check, correctly run, felt like *being verified*.
  > **Having a verification step is not the same as having asked what matters
  > here.**

  **The practical form: name the decision the finding feeds, then verify the input
  to *that*.** For a leak that is `git merge-base --is-ancestor <commit>
  origin/main` — public or not decides *accept* versus *amend*, and nothing else
  about the finding changes the answer.

- **A checker's silence is a finding, and it is the one nobody reads.** A tool
  that *stops* reporting something is telling you the thing you believe has
  changed — but **"clean" reads as "nothing to do"**, not as *"the item you are
  still carrying is no longer true."* So the correction arrives and lands nowhere.

  2026-08-06, and it is this repo's own docs watcher failing at its own job:

  ```
  15:10   drift-check: "--force-wipe is in write-sd-card.sh but in no docs/ flag table"   TRUE
  15:15   10692b2 documents it                                        <- finding expired
  15:43+  every later run: "clean"                                    <- the correction, unread
  ```

  **The checker was right on every single run.** It was run every pass. Its
  silence was the answer, and the finding was still restated as outstanding in
  three later reports — each honestly written and each wrong. **It took a human
  saying so twice.**

  > 🔑 **The mechanism is precise and worth more than the incident: a checker's
  > output is a fact *about one run*, and it was promoted into a standing status
  > line.** A finding is dated. A status is present tense. Copying the first into
  > the second silently strips the date, and nothing in the sentence marks that it
  > happened.

  **Two remedies, and the second is the one with teeth:**

  * **Read a checker's output as a *diff* against last time, not as a list of
    positives.** Something that dropped off is information.
  * **Never carry a finding into a "still outstanding" line from memory —
    re-derive it from the run you just did.** If a status item cannot be traced to
    output in front of you, it is a recollection wearing a report's clothes.

  This is the same shape as *[a finding about a live system is a claim about a
  moment](#improvement-backlog)*, turned inward: there, someone else's repo moved
  under a report; here, **our own tooling corrected us and we did not listen.**

- **Agreement is not corroboration when the instrument is broken.** The rule above
  catches an instrument returning **the same thing for everything**. This one
  catches an instrument returning **the right thing for no reason** — and it is
  nastier, because the usual tell is gone:

  | Rule | Catches | Tell |
  |---|---|---|
  | uniform result across varied inputs | an instrument returning the same thing for everything | implausible sameness |
  | **agreement without corroboration** | an instrument returning the right thing for nothing | **none — it looks like success** |

  2026-08-06: `luna-volume` timed ffmpeg's read of a live stream with busybox
  `date +%s%N`. **Busybox does not support `%N`**, so the timer returned
  `wall=0 ms` for a 15-second fetch *and* a 30-second one. The conclusion it
  produced was *"the fetch is 10× faster than realtime."*

  **That conclusion was directionally correct.** The fetch *is* faster than
  realtime — there is a ~10 s Icecast burst buffer, later measured properly at
  6.6× for a 5 s chunk. **The broken timer agreed with the truth.**

  > **Nothing would have looked wrong until the segments failed to line up** — at
  > which point the search would have started at the segment muxer, several layers
  > from the fault, **with the timer's authority behind the wrong model.** And the
  > right answer for the wrong reason still gives the wrong *magnitude*, so the
  > buffers would have been sized off a number that never measured anything.

  **So: a measurement confirming what you expected is not evidence the instrument
  works.** Validate it against an input whose answer you know **independently of
  the hypothesis** — a known-duration fetch, a file of known size, a delay you
  introduced yourself. **Confirmation is the case where checking feels least
  necessary and is most valuable.**

  Second instance, same family and the same day: a `ps` parse that **counted
  regex matches rather than lines**, against a path
  (`/mnt/anyka_hack/ak_adec_demo/ak_adec_demo`) containing the matched string
  **twice**. One running player read as two. The numbers were wrong and
  *internally consistent*, so nothing looked off.

  A third lives [under the liveness rule](#improvement-backlog) rather than here,
  because it is a *source* rather than an instrument: BusyBox `ftpd`'s `--help`
  claiming *"Anonymous FTP server"* on a build with authentication compiled in.
  **The common shape across all three is the instrument failing while looking
  fine** — and only the first rule in this pair has a symptom you can see.

- **A repo copy and the deployed file are two different things.** The repo `ctl`
  had eight comment lines the camera's copy did not. Editing the device copy and
  committing it would have silently deleted them. Diff before you overwrite, and
  make the two hash the same afterwards.
- **A closed thread is a statement about what someone knew, not a prohibition on
  new information.** *"Nothing further"* means the sender had nothing further —
  it does not mean you should sit on something they had not seen. This happened
  **three times on 2026-08-06**: an agent went back on an explicit *"you're
  clear"* because it had noticed something the instruction did not cover, and
  **all three were right to.** The cost of asking is one message; the cost of
  not asking is a finding that dies in whoever noticed it.

  Ask rather than act, though — reopening a thread is cheap, **acting unasked on
  a closed one is not.**

- **`git commit -o` stops you carrying someone else's work. Nothing stops them
  carrying yours.** Everyone guards the first direction and nobody guards the
  second. It happened here on 2026-08-06: a one-line phrasing fix sat
  uncommitted in `write-sd-card.sh` while a sibling committed that same file,
  and the fix shipped under a message about the speaker volume ladder, which
  never mentions it. Nothing broke — the content was correct and landed on
  `main` — but the change is now attributed to work it has nothing to do with,
  and no amount of `-o` discipline on the *author's* side would have prevented
  it. **The only defence available is committing promptly**, which is why "a
  partial commit that unblocks a sibling beats a complete one that holds the
  file" is an engineering rule and not just courtesy. Corollary: git authorship
  cannot distinguish who did what here — every commit is `jp <jp@jphein.com>` —
  so the commit *message* is the only provenance record, and a message that
  silently covers two people's work has lost it.

---

## The goal: this is a platform, not one repaired camera

JP has **a bag of cheap cameras** — thirteen, of which **exactly one is an
Anyka**. So the unit of work is *a fleet that comes up correct and stays that
way*, not *this camera made to behave*. That reorders everything below — a fix
that only exists on one running device is worth roughly nothing.

> ❌ **This said "a bag of these" until 2026-08-06, meaning a bag of Anykas.**
> There is one. The presumed second was an
> [icam365 in an identical case](hardware.md#-two-vendors-one-case--tell-them-apart-by-oui).
>
> **The framing survives, but by a different route than the one written, and the
> difference matters for what goes at the top of this list:**
>
> * **Weakened:** the card writer, the update tooling and the OTA path now serve
>   **one device**. "It must work across the bag" was doing real ordering work for
>   those, and it no longer applies to them.
> * **Strengthened:** [identity and inventory](identity.md) are now **the only
>   items here that operate at fleet scale** — twelve of the thirteen cameras are
>   ones this repo's transport cannot yet reach.
> * **Newly load-bearing:** with one Anyka and no UART wired to it, **the spare
>   card is that camera's sole recovery path.** There is no second unit to fall
>   back on, and no partition whose loss leaves a reachable device. Anything that
>   risks the card is now a single point of failure rather than an inconvenience.
>
> ⚠️ **I have corrected the premise and deliberately not re-ordered the list**,
> because which of those three effects should dominate is a call about priorities
> rather than a fact about the fleet.

**The test for any change: would a camera taken out of the bag today get it?**

Three consequences worth holding onto:

- **Nothing counts until it is in `tools/write-sd-card.sh`.** Two fixes have
  already nearly been lost by living only on the live card — the boot-time IR-cut
  line (which was never in the backup, so no written card ever had it) and the
  `gergesettings` timezone. Both were caught by luck.
- **The card is the deployment mechanism.** Fixes belong on removable media, not
  the squashfs root: recoverable by pulling the card, survivable when wrong, and
  the same artefact for every unit.
- **Per-unit config must be a parameter, not a default.** `--ssid` is now
  required precisely because a wrong default strands a camera with no network and
  no console. Anything else that varies per camera — SSID, `time_source`,
  hostname — needs the same treatment before the fleet grows.

### Platform gaps, in priority order

1. **A camera has no identity — DONE, see [identity.md](identity.md).** Both
   halves of the split now ship in `tools/write-sd-card.sh`:

   | | Unit | Build |
   |---|---|---|
   | Lives in | `/data/unit.json` (`mtd7`) | `/anyka_hack/build.json` (the card) |
   | Written by | `name-unit.sh`, once, at first boot | the writer, at card-write time |
   | Realm | `fleet` (identity) | `forge` (provenance) |
   | On a card swap | stays with the camera | follows the card |

   A camera out of the bag names itself from its own MAC — no registry, no
   configuration, nothing to keep in sync. `--unit-name` overrides it for a
   camera JP wants to name himself. Read it back with
   `/mnt/anyka_hack/identity/whoami.sh`.

   ⚠️ **Do not move the unit marker to `/etc/jffs2`** — an earlier version of
   this item recommended exactly that, and it was wrong. `/etc/jffs2` is `mtd6`,
   slot **`C`** of the stock updater: any firmware update carrying a `usr.jffs2`
   overwrites the whole partition.

   **What softens that failure, and only here:** the name is *derived* from the
   MAC, so it is idempotent — a wiped marker re-derives the **same** name on the
   next boot. A wipe costs a boot, not an identity. That does **not** hold for
   `--unit-name`; an override is not derivable and a wiped one is gone. Which is
   the argument for leaving cameras self-named unless there is a real reason.

   Two limits worth carrying forward rather than rediscovering:

   - It is a strong spread, **not** a uniqueness proof. `Adjective Noun` draws
     from 1024 combinations and can repeat; the full `Adj Noun · <mac6>` does not
     while MACs are unique. **Never use the bare noun as an identifier.**
   - The word tables are **pinned** (`tools/identity/PINNED.md`). Counts are the
     modulus, so a word added upstream renames every camera. `fleet` is
     size-locked at 32 × 32 by design, which is why it was chosen over `fantasy`.

   Nothing here has run on a camera yet — the device was owned by another agent.
   Watch the boot console for `identity:` lines on the first unit to take a card.
2. **No inventory.** Nothing enumerates which cameras exist, what card each is
   running, or which are behind. On one camera that is fine; on ten it is the
   whole problem. Note there are **three** distinct version-ish facts, and an
   inventory reporting one field called "version" will be wrong about two of
   them: the vendor's `fw_version` (what the flash contains), the card build
   stamp (which commit of this repo wrote the SD card), and the unit identity.
3. **An upgrade path exists — it was never missing, just unread.** This item
   previously said a fix meant writing a new card and physically swapping it.
   That was too pessimistic. `/usr/sbin/update.sh` is a complete self-contained
   updater with **two** entry points, no cloud and no account:

   | mode | trigger | version gate |
   |---|---|---|
   | TF (SD card) | `/mnt/update/update.tar` | `tar_ver != dev_ver` — any change, **including downgrade** |
   | OTA (network) | `/tmp/update.tar` | `tar_ver > dev_ver` — newer only, **but see below** |

   So the task is *packaging for the mechanism that is there*, not designing one.
   Be accurate about the risk: in-place, non-atomic, **no A/B slots, no
   rollback**, and the watchdog is deliberately killed before flashing — safe to
   let finish, dangerous to interrupt. Verification is md5 **only when the
   `.md5` is present** (the check is inside an `if [ -e ]`), and the hash ships
   inside the artefact it verifies: integrity against corruption, not
   authenticity.

   ### 🔴 Two rules that are not optional

   **Never put `usr.jffs2` in a tarball aimed at a hacked camera.** Slot `C` is
   `/etc/jffs2`, and `C=` is a whole-partition erase (`erase_info.start = 0`,
   `length = mtd_info.size`). That partition holds **the entire hack**:
   `time_zone.sh` (the exploit entry point that launches telnet),
   `gergehack.sh`, `gergedaemeon.sh`, `shadow`/`passwd` symlinked to `/etc`
   (the root login), `webui.hash`, `gergesettings.txt` — **and `anyka_cfg.ini`,
   which holds the WiFi SSID and password.**

   So one write costs telnet, the hack, both passwords *and the network
   config*. **A remote flash including slot C is a remote strand**, recoverable
   only by pulling the card or attaching UART. A camera that has lost its SSID
   is this project's signature disaster — it is why `--ssid` is a required
   argument — and it presents as a unit that is simply *gone*: no association,
   no auth failure, no console. The tarball format makes including it the easy
   mistake.

   (Related, smaller: `update_ispconfig()` runs `rm -rf /etc/jffs2/isp*.conf`
   unconditionally on **every** update, even a kernel-only one. And
   `update_factory_data.sh`'s `update_audio_file()` runs
   `rm -rf /data/audio_file/*` — so `/data` survives an update but that
   subdirectory does not.)

   **Do not trust the "newer only" gate.** Line 277 is
   `[ "$tar_ver" \> "$dev_ver" ]` — a **string** compare. Tested in `sh`, `dash`
   and `busybox sh` (the real interpreter) against the installed
   `6.0.24.10_202401091113`:

   ```
   6.0.24.9  > 6.0.24.10 : TRUE    <- a downgrade PASSES the newer-only gate
   6.0.24.10 > 6.0.9.1   : FALSE   <- .24 reads as older than .9
   same prefix, later timestamp : TRUE (correct)
   ```

   It sorts correctly within an identical prefix and inverts when a component
   crosses a digit-width boundary — **and the installed version is already past
   one.** A gate that is right most of the time and silently wrong at the
   boundary is worse than no gate, because it reads as a safety net.

   **Consequence: version comparison belongs to us, not to the device.** The
   enumerator deliberately does *not* order vendor versions — it reports them
   verbatim and flags **divergence across the fleet**. "All report X, cam3
   reports Y" is actionable, needs no ordering, and cannot be wrong. Ordering
   only becomes meaningful once a declared target firmware exists, and there
   isn't one; do not invent one to make a column sortable.

   ### What this does to gaps 1 and 2

   A remote update mechanism with no identity and no inventory is how you brick
   a fleet one camera at a time. **Inventory stopped being a report and became a
   safety interlock** — the thing standing between a correct flash and flashing
   the wrong unit.

   Note the direction, because it inverts the usual argument: *"we can fix it
   remotely"* normally justifies **less** ceremony. Here it justifies **more**,
   because the only thing that previously forced you to identify the right
   camera — physically standing in front of it — has been removed. You can now
   strand a camera from your desk, in one command, with nothing in the way.
4. **Kernel-build variance is real and unmapped.** Two builds already seen —
   2022 `zhoujiahui` (prefixed `gpio-ircut_a`) and 2023 `chensheng` (`ircut_a`
   plus `ircut_b`). The writer detects by node name on every boot, which is right,
   but nobody has surveyed what the bag actually contains.

---

## 1. Day/night switching — TABLED, see issue #2

Filed rather than built. The camera genuinely cannot do it (`gpio-rf_feed`
absent, fallback ADC constant at 2999), and the HA-side implementation is
straightforward but not urgent.

## 2. Speaker volume — ✅ SOLVED 2026-08-06, shipped in `df16c66`

**`ctl` now takes an optional `&level=1..6`** (DAC device volume 0–5), default **4**,
falling back to the default binary on absent/malformed/out-of-range input and to the
stock `/usr/bin` player if a card variant is missing. Six one-byte variants live at
`/mnt/anyka_hack/ak_adec_demo/ak_adec_demo.vol1..6`, the original is kept as `.orig`,
and `/usr/bin` is untouched.

**ASLC was never disabled and never needed to be.** The DAC value goes out via ioctl,
which is *downstream* of the compressor — measured: device volume moved 5 → 1 while
every ASLC parameter stayed byte-identical (`ena:1`, `aslc volume 6`), and JP confirmed
the A/B/A/B alternation audibly. That is also why upstream's pre-attenuate-the-file
workaround cannot work: the file is *upstream* of ASLC.

The `strb → NOP` patch that would have disabled ASLC was **never applied** — its proof
chain (demo struct offset +44 → `filterObj[0xa8]`) was never closed, and it turned out
to be unnecessary. Do not apply it.

**Superseded — "only 6, 4 and 2 have been listened to" is out of date.** JP exercised
the HA slider **across its range** on 2026-08-06 — *"all the volumes worked well on the
ha slider then the speak button"* — corroborated by where the entity was found
afterwards: left at 4, discovered at 1, so he moved **down through** the ladder.

**But "verified" is per path, not global**, and `luna-volume`'s record keeps them apart
because they do not all resolve their level the same way:

| Path | Status |
|---|---|
| `media_player` (passes its own level) | ✅ **verified**, slider exercised across range. Unchanged by the centralisation, so the test still applies |
| **Alive** button (`play`, level *resolved*) | ✅ **verified at both ends** — *"alive works at 1 and 6, volume changes"*. This is the path JP reported broken |
| **Chime** button | ⚪ **by construction, not by test** — same script, same `shell_command`, different `clip`. *"Both buttons verified"* would be one press stronger than the evidence |
| **Speak** button (`say`) | ⚠️ **verified *before* its mechanism changed** — it carried a Jinja template when JP tested it; the centralisation deleted that and moved resolution into `ctl_file()`. Re-verified by stub only, **not by ear** |

> ⚠️ **The Speak row is a real open thread, not a formality.** Risk is low — it now uses
> the same resolver Alive proves — but **it is not the same claim**, and *"it follows
> mechanically"* is exactly the reasoning that produced five wrong path counts in one day.
> It is also a textbook case of the rule above: **the centralisation deleted the mechanism
> the verification was performed against**, so the evidence no longer points at the code
> that runs.

**Still not established:** that the ladder is **evenly graded**, or that **adjacent rungs
are distinguishable** — nobody has tried 3 against 4, and the codec's gain table in the
kernel DAC driver is unread. It could be linear, logarithmic, or bunched at one end.

> 🔑 **"All six work" is not "six perceptually distinct steps".** What is established:
> every rung produces audible output — **rung 1 included, so the bottom of the slider is
> quiet rather than silent** — and the paths honour the entity. **Two rungs at opposite
> ends is not a ladder measurement:** 1-vs-6 says the control *moves*, not that it has
> *steps*.
>
> One separate thing the rung-2 pass did settle: *"audible much softer"* rules out an
> **inverted** mapping, which no off-device test can — those prove the slider maps
> consistently, not the right way round.
>
> **That one-clause upgrade — "all six work" → "six distinct steps" — is the same shape as
> every retraction in this file, except it runs on good news.** Good news outruns its
> evidence just as easily as bad news, and **meets far less resistance doing it.**

The original analysis follows, kept because the reasoning is what made the fix findable.

Automatic Sound Level Control is enabled (`## ASLC OPEN OK ena:1`), so a 10.3 dB
difference measured *in the file on the card* is inaudible coming out. Confirmed:
identical text rendered at gain 0.307 and 1.0 measures −26.7 dB and −16.4 dB mean.

`ak_adec_demo` imports `ak_ao_set_aslc_volume`, `ak_ao_set_dac_volume` and
`ak_ao_enable_eq`, and hardcodes them — usage takes only rate, channels, type and
path. In `main` at `0xa484`, both are `mov r1, #6` immediates: DAC volume 6, ASLC
volume 6, against a range of 0–6. **There is a volume control; it is pinned at
maximum and never exposed on the command line.**

Upstream found the symptom and stopped there. The card's own
`anyka_hack/ak_adec_demo/README.md` says *"it is waaayyyy too loud (this is
probably because volume control fails when running) … so I recommend lowering the
volume of the mp3 file"*. That workaround is self-defeating: attenuating the file
just gives ASLC more headroom to normalise back up, which is exactly the effect
measured here (−26.7 dB vs −16.4 dB in the file, inaudible out of the speaker).

**Patch the card's copy, not `/usr/bin`.** `/mnt/anyka_hack/ak_adec_demo/ak_adec_demo`
is byte-identical to the squashfs original (`21a59c852dfb7af2fbaebd0994e24570`) and
already ships with the hack, so it is the natural seam: recoverable by pulling the
card, and it belongs in `tools/write-sd-card.sh` rather than on one live device.
Each level is a one-byte change (`e3a01006` → `e3a0100N`); invoke by absolute path.

*Refuted:* PATH shadowing. `ctl` does call `ak_adec_demo` by bare name, but every
directory on `PATH` is squashfs, so there is nowhere to put the shadowing binary.

## 3. Watchdog catches death, not hangs

It greps `top` for the process name. The camera's characteristic failure is
**silence with the process alive** — port 3000 stopped listening while
`libre_anyka_app` was still running and RTSP still answering. A liveness probe
that made a real HTTP request would catch what the name check cannot.

## 4. Post-auth hardening in the web UI

Lower priority *because post-auth on this UI already means root by design* — the
`system` CGI exists to run privileged commands. Still worth doing:

- `del_video.sh` interpolates `$file` unquoted into `mv`; `.h264`/`.mp4` is
  appended, so traversal is constrained to relocating files with those suffixes
- the same `$file` is echoed into HTML unescaped (reflected XSS)
- `settings_submit.sh` still has `eval 'echo $'$parameter`, fed from
  `gergesettings.txt` — trusted-ish, hence the low ranking

The pre-auth RCE in `cgi-bin/header` is **already fixed** — do not reopen it, and
do not "tidy" the lowercase-only key filter without re-running the live exploit
payloads. The md5 recorded in the writer is what was actually verified.

## 5. A stop command for audio

Playback is `setsid ak_adec_demo`, fire-and-forget. Nothing can interrupt a clip,
which blocks a real media_player `stop`, and makes streaming seams unfixable.
A `ctl` verb that kills the decoder would close several things at once.

## 6. Streaming / radio

Groundwork exists in `anyka_http.py radio` — chunked fetch, transcode, upload,
play, repeat, with alternating filenames so a playing file is never overwritten.
The seam is the upload (~1 s per chunk). Blocked on (5) for clean stopping.

## 7. The two-timezone wart

`/etc/jffs2/time_zone.sh` exports its own `TZ` for the vendor app's process tree
while `gergehack.sh` exports `$time_zone` for everything it launches. Left alone
deliberately: that file is what the telnet exploit hooks. After November's DST
change expect up to an hour's disagreement between the web UI and the ptz daemon.
Cosmetic; documented so nobody hunts it.

---

## 8. Repo and device can drift, and `write-sd-card.sh` assumes they don't

**Observed, not hypothetical.** The repo's `reference/sd-card-original/web_interface/ctl`
(`17810bd0…`) carried eight comment lines about the ircut direct-write that the
*deployed* copy on the camera (`2b85f044…`) did not. Editing the device copy and
committing it would have silently deleted that comment block — a documentation loss
with no diff conflict to warn anyone. Caught by diffing before overwriting; the change
was merged onto the repo version instead and the device re-flashed from it, so both now
hash `81237ee7…`.

Best guess is the repo copy was edited for comments after the device was last flashed
and never re-deployed — **a guess, not established.** Worth one look, low priority.

**The generalisation is the part that matters:** `tools/write-sd-card.sh` carries md5
constants that assume repo and device agree. If they can drift for `ctl` they can drift
elsewhere, and the writer's gates would then be checking against a stale expectation —
passing while installing something nobody reviewed. Worth an audit of every hardcoded
md5 in that script once the card work settles.

Cheap mitigation if an audit is too much: have the writer *report* the md5 of what it
installed rather than only asserting a constant, so a drift shows up in the output
instead of being silently absorbed.

## Closed — do not reopen

| | |
|---|---|
| White LEDs | Not wired on this PTZ board variant. Vendor firmware says so itself: `onf_shaking_head_cam not support white led`. Expander refuted (nothing answers at 0x58), pin config refuted, share-pin mux refuted with a control. |
| IR LED ring | Dark. Confirmed by JP with a phone whose IR sensitivity is independently established. |
| `gpio-rf_feed` | No counterpart exists. **Do not point it at another name** — that converts a clean `ENOENT` into a silent wrong-pin write, which is strictly worse. |
| Daemon IR-cut path | Every route dies at the same `ak_drv_ir_init` check: `ptz_daemon`, `libre_anyka_app`, and the vendor's own `ak_drv_ir_demo`. One bug, three binaries, six library builds. `ctl` bypasses it with a direct pin write. |
| `libplat_drv.so` rename | **Regression.** Renaming `gpio-ircut_b` flips init into two-line mode, which pulses 10 ms and releases both pins — parking the filter out permanently. Renaming `ircut_a` alone would land in write-and-hold, but the direct write in `ctl` is simpler and already proven. |
