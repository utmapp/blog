---
title: "Announcing UTM Games Database"
subtitle: "Autonomous driver improvements and the future of UTM development"
date: 2026-11-07
human: osy
ai: claude-opus-5-5
tags: [gamesdb,graphics,testing]
---

Last month, we released [UTM 5](https://docs.getutm.app/updates/v5.0/) which, amongst other things, is the first UTM release to ship accelerated graphics for Linux (Vulkan 1.3) and Windows (DirectX 11-12). In fact, we are the first virtualization product on macOS to ship DirectX 12 (ahead of VMware Fusion and Parallels Desktop). But shipping the driver is just the first step for a free open source PC replacement for macOS. Maintaining, supporting, and patching issues for the library of over 200,000 Windows games is an ongoing challenge. That is why we are launching [db.getutm.app](https://db.getutm.app), a community driven game compatibility database for UTM. Users can submit issues they run into and star the games they care about. This will influence the priority and direction of driver development. The site is also more than a passive database cataloguing issues. If a report is filed for a game that @UTMapp owns on Steam, an agent will autonomously reproduce the issue, triage it, and develop a driver fix which will be sent to a human to review and merge. This allows the UTM graphics drivers to be developed continuously 24/7 with complete transparency.

<video class="author-human" src="/assets/images/posts/gamesdb/demo.mp4" autoplay loop muted playsinline style="max-width:100%;height:auto;"></video>

<aside class="aside">
  <strong>Reader's note —</strong>
  posts on this blog are jointly authored. The blue gutter line marks
  paragraphs written by a human contributor; the orange line marks
  paragraphs drafted by an AI collaborator.
</aside>

## Challenges of graphics driver work

Graphics driver development is hard. There is a reason that only a handful of companies in the world work on it. As an example, Intel [talked about fixing GTA 5 compatibility issues for Arc](https://youtu.be/91SxN7Ub5X4?t=150) and said that MSAA performance issues came down to the specific implementation in GTA 5 (even though MSAA works fine in general). On the other side, NVIDIA [runs over 1,000 tests a day across 4,500 configurations](https://youtu.be/u1BOC6oMCz4?t=204) and works with the developers to fix and optimize games. Developing optimized drivers therefore typically involves large teams of dedicated testers and large teams of talented developers. We are an open source project with very little capital and resources and therefore need to get creative.

Let's break down the problem and see where the difficulty lies.

1. **DirectX is complex**: DirectX 12 has over 100 interfaces and over 350 unique methods, and DirectX 11 has about the same. We can depend on compatibility layers such as [D3D9On12](https://github.com/microsoft/D3D9On12) for older APIs, but there are still plenty of legacy interfaces that must be supported. The real complexity is not in the sheer number of API calls but in the fact that internal state is maintained through these calls. This means that the order of the calls matters. For testing, you have millions of cases to run. Worse yet, it is not always clear what a "failing" test is like. A game crash or black screen is easy to detect when you run millions of tests a day, but how do you effectively detect missing geometry or incorrect colours or micro-stutters?
2. **Number of games**: From the Gamers Nexus clip above, we got a taste of what graphics driver testing is like. In that example, a single game (GTA 5) had MSAA performance issues that don't hit any other game. Worse yet, they also mention instances of a particular configuration of a game having driver issues while other configurations works fine. This is why NVIDIA hires teams of dedicated game testers to play games and record issues. Another roadblock that might be overlooked is the cost of purchasing games to test. If we want to test 100 games at $20 each, that is already $2,000 of cost: nothing for a corporation but a good chunk of money for the rest of us. And to nip it in the bud: no, we cannot just pirate the games, because even though [large corporations](https://www.wired.com/story/new-documents-unredacted-meta-copyright-ai-lawsuit/) are allowed to break the law, we have to play by the rules.
3. **Driver development is hard**: This was touched upon in the [previous post]({% post_url 2026-07-24-bringup-notes-building-triton %}). In short, WDDM driver development is a highly specialized subject and the experts all work at large companies with strict NDAs. Additionally, companies like NVIDIA and AMD partner with game developers directly to help optimize their games. We cannot assume that an open source project will get that level of attention. Writing the driver code is just part of the story. Debugging and testing the code is a challenge in itself. We have to debug Windows kernel drivers from one VM to another using KDNet. For performance issues, we need to use ETW, which requires bringing up performance monitor events in QEMU. Debugging memory issues often requires digging into QEMU itself which is not friendly with LLDB due to its use of user signals for IPI handling. At the host side, if we use D3DMetal that means debugging a Rosetta translated process without source code or symbols. On top of all that, the UTM GUI, QEMU, and virglrenderer all run in different processes (with virglrenderer running under Rosetta when D3DMetal is used). We had to invent debug flows and tooling from scratch to cover all of this.

## DirectX CTS

Before we can even start to chip away at game compatibility, we need a baseline working implementation of DirectX DDI. This is what our driver, [Triton]({% post_url 2026-07-24-introducing-triton-directx-11-driver-for-qemu %}) is designed to do. But how do we know that Triton is working correctly? In the bring-up, we relied on a small set of hand-picked benchmarks and games. That worked well enough to exercise the most common paths in the driver which covers the majority of day-to-day use. However, more complex games and workloads will exercise less common paths in the driver and there is no way to know what subset of games we need to test before we can reach good coverage. In the Vulkan world, this issue is solved by the [CTS](https://github.com/KhronosGroup/VK-GL-CTS/blob/main/external/vulkancts/README.md) (Conformance Test Suite). The CTS contains test cases for every requirement in the Vulkan specification and its extensions. In order for your driver to be certified by Khronos Group, it must pass a certain number of these tests. In the DirectX world, the analog to this is the [WHCP (née WHQL)](https://learn.microsoft.com/en-us/windows-hardware/design/compatibility/whcp-certification-process) (Windows Hardware Certification Program) which requires running the HLK (Windows Hardware Lab Kit) on your driver. For various reasons, the HLK is difficult to work with. To start, you need a separate machine running Windows Server (x64) to host the HLK Controller. Only the Controller can drive the tests on the test machine. When certain prerequisites fail, many tests are skipped and debugging test failures is a pain. There are also many tests for WDDM beyond DirectX which would take too much effort to address and does not impact running 3D applications.

This is why we created [directx-cts](https://github.com/osy/directx-cts), a custom runner for HLK tests that can run free-standing. The project includes shim libraries to run the tests without the HLK Controller as well as in-process patches to disable certain prerequisite checks. It includes scripts to download all the DirectX test cases from Microsoft directly without installing the full 4GB. It also can run in Wine/CrossOver which is tremendously useful because in order to narrow down a test failure to the right part of the stack, it is useful to run it in Wine which loads the host library (D3DMetal or DXMT) directly. If the same test passes in Wine but fails in a Windows VM, that means the error is most likely in Triton, our Windows DDI driver. In order to test the runner itself, we also run it on WARP, Microsoft's software DirectX reference implementation. During the development of `directx-cts`, we found and fixed many issues in Triton (especially around D3D9On12) and the following results are from after all the driver fixes.

### Baseline Test Results

Three configurations were tested:
{:.author-ai}

| Configuration | What renders | How the tests run |
|---|---|---|
| **WARP** | Microsoft's WARP software rasterizer (CPU only) | Windows 11 (arm64, build 26100) VM with no GPU driver installed. This is the reference result. |
| **D3DMetal 3.0 under Triton** | Apple's D3DMetal 3.0 on the Mac's GPU | Same Windows 11 arm64 VM with the Triton paravirtualized GPU driver installed. Direct3D 9 goes through Microsoft's D3D9On12 layer. |
| **D3DMetal 3.0 under CrossOver** | Apple's D3DMetal 3.0 on the Mac's GPU (Direct3D 10–12); Wine's wined3d (Direct3D 9) | CrossOver (Wine) on macOS, no VM. The tests are x64 and x86 Windows binaries translated by Rosetta 2. |
{:.author-ai}

Both D3DMetal configurations use the same D3DMetal 3.0 binary. The host is an Apple M4 Pro running macOS 15.6.
The runs were done on commit `e8fa0a307a998ee616342f076b87a2ab41a84e89` of directx-cts. Triton running Oct 15, 2026 driver.
{:.author-ai}

#### Results

| Configuration | Pass | Fail | Skip | Total | Pass rate |
|---|---:|---:|---:|---:|---:|
| WARP | 1,362,543 | 4,757 | 402,139 | 1,769,609 | 99.65% |
| D3DMetal 3.0 under Triton | 2,072,562 | 231,955 | 371,105 | 2,675,876 | 89.93% |
| D3DMetal 3.0 under CrossOver | 1,612,386 | 462,003 | 271,940 | 2,466,100 | 77.73% |
{:.author-ai}

**Pass rate** = pass / (pass + fail). Skipped cases are cases the test itself decided not to
run, usually because the device reports that it does not support a feature or format. They
are not counted as failures.
{:.author-ai}

**Total** also includes a small number of "blocked" cases, where a test could not reach its
first verdict: 153 on WARP and 251 on Triton. On CrossOver there are 119,765 blocked cases,
almost all of them from DirectML-based tests, because DirectML is not available under Wine.
{:.author-ai}

The totals differ between configurations because each test lists its cases based on what
the device says it supports. A device that reports more features gets more cases. The
Direct3D 9 tests also only run on Triton and CrossOver (see below). So the pass rate is the
better number to compare, not the raw counts.
{:.author-ai}

#### By API

The three configurations do not cover the same APIs, so here is the same data split by API:
{:.author-ai}

| Configuration | Direct3D 9: pass / fail | Direct3D 9 pass rate | Direct3D 10/11/12 + DXGI: pass / fail | Direct3D 10/11/12 pass rate |
|---|---:|---:|---:|---:|
| WARP | not run¹ | – | 1,362,543 / 4,757 | 99.65% |
| D3DMetal 3.0 under Triton | 1,263,095 / 21,432 | 98.33% | 809,467 / 210,523 | 79.36% |
| CrossOver | 1,046,735 / 8,926 | 99.15%² | 565,651 / 453,077 | 55.53% |
{:.author-ai}

¹ With no GPU driver installed, Windows exposes no Direct3D 9 adapter, so all of the
Direct3D 9 tests are excluded from the WARP run.
{:.author-ai}

² D3DMetal 3.0 has no Direct3D 9 support. CrossOver's Direct3D 9 numbers measure Wine's own
Direct3D 9 implementation (wined3d), not D3DMetal.
{:.author-ai}

#### Triton Differential

Each test case was matched across configurations by its group and full set of parameters.
Cases were matched by their name when a test does not log its parameters.
{:.author-ai}

| Comparison | Cases that pass on the reference | …and fail on Triton | …pass on Triton | …are skipped on Triton | …were not run on Triton |
|---|---:|---:|---:|---:|---:|
| Pass on WARP | 1,362,896 | **192,584** | 781,871 | 33,276 | 355,165 |
| Pass on CrossOver | 1,611,968 | **17,556** | 1,285,284 | 1,013 | 308,074 |
{:.author-ai}

Of the 17,556 cases that pass on CrossOver and fail on Triton, 16,656 are Direct3D 9 tests,
where CrossOver uses wined3d rather than D3DMetal. Only **900** are Direct3D 10/11/12 tests,
where both sides use the same D3DMetal 3.0.
{:.author-ai}

The important takeaway of these baseline CTS results is that running the same backend (D3DMetal 3.0), Triton matches the correctness of Wine. The remaining failures are in the backend itself, which in D3DMetal's case can only be fixed by Apple. However, passing CTS is not a bulletproof measure of driver correctness. One gap in the tests is that many of the cases pass with a visual comparison of 80% or higher similarity. That means there could be plenty of false negatives. Another gap is that the tests are mostly designed around exercising APIs and not end-to-end tests that cover the complexity of DirectX internal states. Additionally, tests are skipped when certain features are not advertised but games often do not react to feature flags in the same way. Although these results give us more confidence in the correctness of Triton, we cannot treat it as a shortcut for game compatibility.

## UTM Games Database

We designed [db.getutm.app](https://db.getutm.app) to crowd-source the solution. We want to leverage the existing large user base of UTM to learn about:

1. What games have issues? Users are encouraged to go on the site, find the game, and report any issues they run into (crashes, incorrect graphics, performance, etc). Negative reports are also useful (game runs without any observable issue on a specific version/configuration). Multiple reports should be filed for multiple distinct issues. Other users can comment on the reports adding their own configuration (working or not), contribute any workarounds, or just add a +1 to indicate they are hitting the same issue.
2. What games do people want to play? Users can star games they care about which will help us prioritize fixing issues. A game must have at least one report before others can star it so if you don't see your favourite game listed, test it out first and add the first report (even if it is "works correctly").

Once we have information on where the issues are, the next step is fixing it. For that, we created the Auto-Triage bot, an autonomous agent that runs in Claude Code, infused with skills distilled from months of driver development and debug sessions. The bot picks up reports, attempts to reproduce the issue, develops a fix, validates it, and finally submits the patch for human review. The pipeline is shown below.

<div class="chart-frame">
  <svg viewBox="0 0 760 1126" width="100%" height="1126" preserveAspectRatio="xMidYMid meet" font-family="-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, 'Helvetica Neue', Arial, sans-serif" role="img" aria-labelledby="gdb-flow-title" xmlns="http://www.w3.org/2000/svg">
    <title id="gdb-flow-title">Auto-Triage pipeline: a report is queued, picked up by a test machine, reproduced, fixed across the driver stack, validated, checked by an independent agent (a failed check sends it back to the triage agent), proposed as pull requests, and shipped in an update. Side branches: needs clarification, cannot reproduce, not to fix; these outcomes go through the same check before they are posted.</title>
    <defs>
      <marker id="gdb-arrow" markerWidth="8" markerHeight="8" refX="5.5" refY="3" orient="auto-start-reverse">
        <polygon points="0 0, 6 3, 0 6" style="fill:var(--text-faint)"/>
      </marker>
      <filter id="gdb-shadow" x="-20%" y="-50%" width="140%" height="200%">
        <feDropShadow dx="0" dy="1" stdDeviation="1.5" flood-color="#0b1020" flood-opacity="0.07"/>
      </filter>
    </defs>

    <!-- main path -->
    <g>
      <rect x="90" y="10" width="320" height="56" rx="14" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#gdb-shadow)"/>
      <text x="250" y="34" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Report submitted</text>
      <text x="250" y="53" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">for a game with Auto-Triage available</text>
    </g>
    <line x1="250" y1="66" x2="250" y2="100" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <g>
      <rect x="90" y="100" width="320" height="72" rx="14" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#gdb-shadow)"/>
      <text x="250" y="124" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Queued for a test machine</text>
      <text x="250" y="143" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">waits for a machine with the right tools and license</text>
      <g transform="translate(205 150)"><rect width="90" height="18" rx="9" style="fill:color-mix(in srgb, var(--text-muted) 14%, transparent);stroke:color-mix(in srgb, var(--text-muted) 45%, transparent)" stroke-width="1"/><text x="45" y="13" text-anchor="middle" style="fill:var(--text-muted)" font-size="11" font-weight="600">Pending</text></g>
    </g>
    <line x1="250" y1="172" x2="250" y2="206" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <g>
      <rect x="90" y="206" width="320" height="72" rx="14" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#gdb-shadow)"/>
      <text x="250" y="230" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Install and reproduce</text>
      <text x="250" y="249" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">the agent installs the game and follows the report</text>
      <g transform="translate(200 256)"><rect width="100" height="18" rx="9" style="fill:color-mix(in srgb, var(--accent) 14%, transparent);stroke:color-mix(in srgb, var(--accent) 45%, transparent)" stroke-width="1"/><text x="50" y="13" text-anchor="middle" style="fill:color-mix(in srgb, var(--accent) 70%, var(--text))" font-size="11" font-weight="600">In progress</text></g>
    </g>
    <line x1="250" y1="278" x2="250" y2="312" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <g>
      <path d="M250 312 L340 348 L250 384 L160 348 Z" style="fill:var(--surface-sunken);stroke:var(--text-faint)" stroke-width="1.5"/>
      <text x="250" y="353" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Reproduced?</text>
    </g>
    <text x="262" y="408" style="fill:var(--text-muted)" font-size="11" font-weight="600">yes</text>
    <line x1="250" y1="384" x2="250" y2="420" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>
    <text x="372" y="342" style="fill:var(--text-muted)" font-size="11" font-weight="600">no</text>
    <line x1="340" y1="348" x2="440" y2="348" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <!-- branch: needs clarification / cannot reproduce -->
    <g>
      <rect x="440" y="300" width="300" height="96" rx="14" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5" stroke-dasharray="5 4"/>
      <text x="590" y="324" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Asks for more details</text>
      <text x="590" y="343" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">a comment on the report</text>
      <g transform="translate(518 350)"><rect width="144" height="18" rx="9" style="fill:color-mix(in srgb, #e58a1a 18%, transparent);stroke:color-mix(in srgb, #e58a1a 45%, transparent)" stroke-width="1"/><text x="72" y="13" text-anchor="middle" style="fill:color-mix(in srgb, #e58a1a 70%, var(--text))" font-size="11" font-weight="600">Needs clarification</text></g>
      <text x="590" y="386" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">or, if nothing more can be tried:</text>
    </g>
    <line x1="590" y1="396" x2="590" y2="424" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>
    <g>
      <rect x="440" y="424" width="300" height="48" rx="14" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5" stroke-dasharray="5 4"/>
      <g transform="translate(524 439)"><rect width="132" height="18" rx="9" style="fill:color-mix(in srgb, var(--text-muted) 14%, transparent);stroke:color-mix(in srgb, var(--text-muted) 45%, transparent)" stroke-width="1"/><text x="66" y="13" text-anchor="middle" style="fill:var(--text-muted)" font-size="11" font-weight="600">Cannot reproduce</text></g>
    </g>
    <path d="M440 324 C 426 324, 426 250, 412 250" style="fill:none;stroke:var(--text-faint)" stroke-width="2" stroke-dasharray="5 4" marker-end="url(#gdb-arrow)"/>

    <g>
      <rect x="90" y="420" width="320" height="72" rx="14" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#gdb-shadow)"/>
      <text x="250" y="444" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Develop fix across the driver stack</text>
      <text x="250" y="463" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">guest drivers, host runtime, hypervisor, etc</text>
      <g transform="translate(200 470)"><rect width="100" height="18" rx="9" style="fill:color-mix(in srgb, var(--accent) 14%, transparent);stroke:color-mix(in srgb, var(--accent) 45%, transparent)" stroke-width="1"/><text x="50" y="13" text-anchor="middle" style="fill:color-mix(in srgb, var(--accent) 70%, var(--text))" font-size="11" font-weight="600">In progress</text></g>
    </g>
    <line x1="250" y1="492" x2="250" y2="526" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <g>
      <path d="M250 526 L340 562 L250 598 L160 562 Z" style="fill:var(--surface-sunken);stroke:var(--text-faint)" stroke-width="1.5"/>
      <text x="250" y="567" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Fixable?</text>
    </g>
    <text x="262" y="622" style="fill:var(--text-muted)" font-size="11" font-weight="600">yes</text>
    <line x1="250" y1="598" x2="250" y2="634" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>
    <text x="372" y="556" style="fill:var(--text-muted)" font-size="11" font-weight="600">no</text>
    <line x1="340" y1="562" x2="440" y2="562" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <!-- branch: not to fix -->
    <g>
      <rect x="440" y="520" width="300" height="84" rx="14" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5" stroke-dasharray="5 4"/>
      <text x="590" y="544" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Closed with a reason</text>
      <text x="590" y="563" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">e.g. a hardware limitation</text>
      <g transform="translate(545 570)"><rect width="90" height="18" rx="9" style="fill:color-mix(in srgb, #d4332a 18%, transparent);stroke:color-mix(in srgb, #d4332a 45%, transparent)" stroke-width="1"/><text x="45" y="13" text-anchor="middle" style="fill:color-mix(in srgb, #d4332a 70%, var(--text))" font-size="11" font-weight="600">Not to fix</text></g>
    </g>

    <g>
      <rect x="90" y="634" width="320" height="72" rx="14" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#gdb-shadow)"/>
      <text x="250" y="658" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Validate the fix</text>
      <text x="250" y="677" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">full test matrix, benchmarks and a code review</text>
      <g transform="translate(200 684)"><rect width="100" height="18" rx="9" style="fill:color-mix(in srgb, var(--accent) 14%, transparent);stroke:color-mix(in srgb, var(--accent) 45%, transparent)" stroke-width="1"/><text x="50" y="13" text-anchor="middle" style="fill:color-mix(in srgb, var(--accent) 70%, var(--text))" font-size="11" font-weight="600">In progress</text></g>
    </g>
    <line x1="250" y1="706" x2="250" y2="740" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <g>
      <rect x="90" y="740" width="320" height="72" rx="14" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#gdb-shadow)"/>
      <text x="250" y="764" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Independent result check</text>
      <text x="250" y="783" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">a second agent checks the result against the evidence</text>
      <g transform="translate(200 790)"><rect width="100" height="18" rx="9" style="fill:color-mix(in srgb, var(--accent) 14%, transparent);stroke:color-mix(in srgb, var(--accent) 45%, transparent)" stroke-width="1"/><text x="50" y="13" text-anchor="middle" style="fill:color-mix(in srgb, var(--accent) 70%, var(--text))" font-size="11" font-weight="600">In progress</text></g>
    </g>
    <line x1="250" y1="812" x2="250" y2="846" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <g>
      <path d="M250 846 L340 882 L250 918 L160 882 Z" style="fill:var(--surface-sunken);stroke:var(--text-faint)" stroke-width="1.5"/>
      <text x="250" y="887" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Verified?</text>
    </g>
    <text x="262" y="942" style="fill:var(--text-muted)" font-size="11" font-weight="600">yes</text>
    <line x1="250" y1="918" x2="250" y2="954" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>
    <text x="112" y="874" style="fill:var(--text-muted)" font-size="11" font-weight="600">no</text>
    <path d="M160 882 H60 V456 H88" style="fill:none;stroke:var(--text-faint)" stroke-width="2" stroke-dasharray="5 4" marker-end="url(#gdb-arrow)"/>

    <!-- note: the side branches are checked too -->
    <g>
      <rect x="440" y="740" width="300" height="72" rx="14" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5" stroke-dasharray="5 4"/>
      <text x="590" y="764" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Every outcome is checked</text>
      <text x="590" y="783" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">the outcomes on this side too are verified</text>
      <text x="590" y="800" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">before the comment and status are posted</text>
    </g>

    <g>
      <rect x="90" y="954" width="320" height="72" rx="14" style="fill:var(--accent-tint);stroke:var(--accent)" stroke-width="1.5" filter="url(#gdb-shadow)"/>
      <text x="250" y="978" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600">Pull requests opened</text>
      <text x="250" y="997" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">maintainers review the change</text>
      <g transform="translate(200 1004)"><rect width="100" height="18" rx="9" style="fill:color-mix(in srgb, #2a8f4a 18%, transparent);stroke:color-mix(in srgb, #2a8f4a 45%, transparent)" stroke-width="1"/><text x="50" y="13" text-anchor="middle" style="fill:color-mix(in srgb, #2a8f4a 70%, var(--text))" font-size="11" font-weight="600">Fix proposed</text></g>
    </g>
    <line x1="250" y1="1026" x2="250" y2="1060" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#gdb-arrow)"/>

    <g>
      <rect x="90" y="1060" width="320" height="56" rx="14" style="fill:var(--accent);stroke:var(--accent)" stroke-width="1.5" filter="url(#gdb-shadow)"/>
      <text x="250" y="1084" text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="600">Shipped</text>
      <text x="250" y="1103" text-anchor="middle" style="fill:var(--accent-on)" font-size="11">in a future UTM release or driver update</text>
    </g>
  </svg>
</div>

### Worked Example

To see the Auto-Triage bot in action, take a look at [this report](https://db.getutm.app/games/134583-forspoken/reports/4) for the game "Forspoken". The user written report is as follows:

> The game crashes whenever I open the display settings. Everything else in the options works, and the game itself runs fine on D3DMetal. When I open Display Settings the Resolution line shows 0x0, and a second later the game shows an error box saying DXGI_ERROR_DEVICE_RESET (sometimes it just closes instead). I can't change the resolution or the screen mode because of this.

This is a good example of what we look for in a report. A good report does not have to be lengthy but provides enough details to reproduce. It clearly indicates what the issue is and where it occurs. Since there was an error message, that was included as well as what was observed. The expected behaviour is obvious in this context but is also provided to remove any ambiguity. This report did not come with any screenshots, recordings, or logs but those artifacts would be helpful if the issue was more difficult to reproduce.

Soon after the report was posted, the Auto-Triage bot set the report to "in progress" because it recognized that a demo of the game was available on Steam. After it reproduced the issue, it posted a comment detailing the reproduction procedure. If the bot's Steam account does not own the game and there is no demo available, the bot will try its best to distil any information from the user's attachments (which is never shown publicly) while stripping any sensitive information. For example, if an attached log gives a precise DirectX error, that would be included in the bot's comment. The intention for this is that anyone who owns the game can try to triage the issue themselves (or run their own instance of the bot) and propose a fix.

A few hours after, the bot identified and [proposed a fix](https://github.com/osy/virtio-win-mesa/compare/neptune...UTMapp-bot:virtio-win-mesa:triage/report-4-dealloc-by-resource) for the first issue. It was able to create a minimum reproducing application and fix the application crash.

At this point, the bot claimed the work is complete but the separate validation bot kicked it back correctly objecting that one issue was fixed ("DXGI_ERROR_DEVICE_RESET") but another was still unfixed ("Resolution line shows 0x0"). The triage bot then continues the work and comes up with three more patches across the kernel driver, the host renderer, and QEMU display path.

This relatively complex triage, development, and debug scenario all happened without any human intervention in the span of a day. Before declaring the issue fixed, the bot also did some basic benchmark validation (to make sure no regressions) as well as an automated code-review (which turned up some issues such as a similar bug in the D3D11 path). The final patches are public for anyone to test but eventually they will be human reviewed and integrated into the next UTM release.

### Donating Games

The bot can only test games that it owns on the @UTMapp Steam account. If the game is not owned, the bot will try its best to come up with a synthetic reproduction given just the logs and other artifacts. You can also gift a copy of the game to @UTMapp and alert it about the gift from the game page ("Donate a copy" button). If the game was previously unowned, then it will queue up triage of the submitted reports in the order of the highest number of comments/+1s.

### utmapp-bot

If you have spare AI tokens and a spare Mac, you can [run the bot yourself](https://github.com/utmapp/utmapp-bot). Note that currently you will only be allowed to access the public facing report/comments and not the private attachments. The utmapp-bot Claude plugin is designed from the months of experience bringing up Neptune and Triton. Session logs and artifacts were analysed by Claude and the skills were crafted to avoid pitfalls and wasted cycles. It also includes verification and validation skills distilled from many code review sessions and augments `/code-review` with extra details that Claude seems to always miss when reviewing code written for this stack. One example is the following directive:

> Variant analysis: fix the related paths too. A bug in one function is often in its siblings: the other API versions (D3D11 and D3D12), the create and destroy halves, the shared and non-shared paths, the other formats or resource kinds handled by the same code, and code that was copied from it. Search for them and fix the ones that have the same bug. A synthetic test of those paths (/utmapp-bot:write-gpu-probe) is recommended, not required.
{:.author-ai}

This came from the fact that often we would fix an issue on the D3D11 path and later find it again in D3D12 or vice versa. Another example is this:

> Weigh what it finds in this order: performance, robustness, correctness. Fast code that handles 99% of cases and never crashes beats covering the last 1% with a lot of extra code that can regress other paths.
{:.author-ai}

This line came from insight on which code review changes were accepted and which were rejected.

#### Note on AI usage

In a previous post, I made [the following observation]({% post_url 2026-07-24-bringup-notes-building-triton %}):
> I have been thinking about how in the early days, people programmed in machine code. Then assembly code was invented to abstract away the encoding of instructions so human can focus on the semantics. Then higher level languages like C and Python were invented so humans can focus on the logical structure rather than the semantics. Now, with AI assistants, we can focus on the design and architecture rather than the logical structures.

Once upon a time, seasoned programmers scoffed at these kids who never wrote assembly and depended on the "compiler" to convert their C code into machine code. "Real" programmers know how to write assembly and your "compiled" code will never be as performant as my hand rolled assembly. Of course, nobody could claim that now as modern C compilers can generate far more optimized machine code than most people can. I see a similar trajectory for LLM coding tools. When I [started building Neptune]({% post_url 2026-05-16-introducing-neptune-direct3d-virtualization-for-qemu %}) with Opus 4.6, the conclusion was:

> Claude is most effective when the human _treats it as an extremely fast, extremely literal junior engineer with no memory of past sessions and no judgement about when to stop_
{:.author-ai}

but:

> I don’t think human software engineers are ever going away. I think as the models get better, humans must get better as well.

At the time, I thought Claude was good at executing but not planning. When given a complex stack with many moving parts, it will often put code in the wrong place or introduce hacks/workarounds while claiming to solve the problem. Code review sessions were multiple hours of reading followed by extensive back and forth and multiple iterations of rewrites before the code got to a point that I could accept. Thinking back to that time and the amount of slop projects coming out, I wonder how many of those projects have now been abandoned. Fast forward to present day with Opus 5.5 and Fable 5.1, I have to say that more often than not, the code Claude writes is something I am willing to accept--and if not, usually one round of `/code-review` will sort it out. In fact, I must admit that it is writing better code than I can in many ways. I know this because I have read more code than most people and so I try to set a high standard for myself. Most programmers (including myself) cannot write clean, concise code, with minimal bugs better than a model at the level of Opus 4.5. That's why I was not surprised at the amount of manual code review I had to do even when others were shipping vibe coded crap to prod. However, it was surprising to me that the models have gotten so much better so quickly. I think the turning point for many was when [Linus Torvalds accepted AI generated code in the Linux Kernel](https://lore.kernel.org/linux-media/CAHk-=wi4zC+Ze8e+p3tMv8TtG_80KzsZ1syL9anBtmEh5Z40vg@mail.gmail.com/) because the Linux Kernel has always tried to maintain good code quality.

So how do humans get better? One avenue I am betting on is maintenance. I don't just mean fixing bugs, updating the website, patching security vulnerabilities. Those things will easily be taken over by AI. What I mean is building trust in a project, keeping it running for many years, and creating a community that can build on top of it. I just don't think most vibe coders have what it takes to maintain a software project. It is easy to churn out slop, but most of the slop will be abandoned in a few months. So how do you maintain a software project in the age of slop? I don't have a perfect answer to this but I will tell you a few things that I am trying to do for UTM.

* **Open source the processes and methodology** I believe the source code is just one piece of a project. There is a lot of tribal knowledge, lessons learned, and mistakes made throughout the years that needs to be codified into contribution guidelines, extensive documentation, AI skills, and more. A new contributor should not have to search chat rooms and mailing lists to understand why a particular decision was made. For UTM, this includes our [design philosophy](https://github.com/utmapp/UTM/blob/main/CONTRIBUTING.md#design-philosophy), open sourcing all aspects of our infrastructure including the [GitHub runners provisioning scripts](https://github.com/utmapp/utmapp-runner) and now the [utmapp-bot](https://github.com/utmapp/utmapp-bot) for debugging and testing. Another benefit of keeping all this data publicly accessible is that the agents working on the code are able to make better design decisions. In fact, the quality of pull requests to UTM has gone significantly up since we added our contribution guidelines and `/utm-review` skill. I think lowering the friction for contribution while maintaining quality should be the goal of all open source projects. Misguided attempts to close off all AI contribution is partially the fault of low effort AI users but also partially the fault of maintainers not properly defining their standards of quality and automating the enforcement of that quality.
* **Setting a vision** While AI can follow contribution guidelines and enforce standards, they cannot evolve the project without guidance from the humans who care about it. Should UTM be ported to a new platform? When can we deprecate an older version? These are examples of decisions that should be made by maintainers (along with community feedback) not by an AI agent following a recipe or pure majority votes. The maintainers are the tastemakers for the project. They should incorporate community feedback but also know where the project needs to go even if it may not be a popular decision. AI can write code and review code and even design projects but AI will never be able to _curate_ better than experienced humans for the same reason why it cannot draw meaningful pictures or write engaging stories: it lacks creativity. Code is judged by how well it works and because that is a universal metric, it will get better at doing it. But AI's creativity can only be an approximation of what humans can intuit. That may be enough to fool non-curious people but as long as humans fail to agree on a metric for creativity, AI will never be able to do it.
* **Accelerating development** In order to support more changes and larger changes in each release, we need to fortify the foundations. `utmapp-bot` is one part of this effort: it includes `/test-utm-ui` which validates UI changes across multiple macOS versions, iOS versions, and visionOS. One of the biggest headaches working with SwiftUI is that often layouts will change subtly between different OS versions. Since time is spent mostly testing on the latest version, issues are not caught until they get shipped and it breaks someone's setup. Admittedly, this is not good practice and going forward all changes that affect the UI will be automatically validated by a machine that runs this skill. Next, an outstanding issue for five years [was finally completed](https://github.com/utmapp/UTM/issues/2565): add a test suite to UTM. This has been another point of shame but writing tests has always been something that was put off in favour of new features and the list of things that require tests steadily grew. Claude was able to analyze the history of commits and closed issues and make a test plan that would have covered most of the issues that have shipped in the past as well as guidelines for when to add new tests in the future. From this point forward, we will require tests when they meet those guidelines. The goal is to not only automate much of the development process but also automate most of the testing and validation.

## Closing thoughts

The UTM 5 release contained a record number of external contributors and we anticipate the next one to have even more. We think that the improvements in testing and automated validation will help both maintainers and contributors. Thank you to everyone who helped make UTM 5 possible!
