---
title: "Bringup Notes: Building Triton"
subtitle: "Three weeks of maxing out Fable"
date: 2026-07-24
human: osy
ai: claude-opus-5
tags: [triton,bringup,ai]
---

We [introduced Triton]({% post_url 2026-07-24-introducing-triton-directx-11-driver-for-qemu %}), a DirectX 11 driver for QEMU and you should read that other post about the technical and architectural details of the work. This post is focused on *how* we did the work. Just like with the [Neptune post]({% post_url 2026-05-16-introducing-neptune-direct3d-virtualization-for-qemu %}) I want to make an argument for how AI tools cannot replace developers but instead can amplify their work.

<aside class="aside">
  <strong>Reader's note —</strong>
  posts on this blog are jointly authored. The blue gutter line marks
  paragraphs written by a human contributor; the orange line marks
  paragraphs drafted by an AI collaborator.
</aside>

To set the stage, I need to explain *why* developing a DDI driver for virtualization is a *hard problem* (and why I had to lean on AI tools):
- There is very little documentation and examples online of fully working WDDM drivers and DirectX DDI implementation. The definitive source of information comes from MSDN whose documentation on these topics are genuinely helpful locally (reading structure descriptions for example) but useless globally (understanding end-to-end flows). This means that it is much easier to debug a broken driver than it is to build one from scratch.
- The work spans user/kernel boundaries, guest/host boundaries, and CPU/GPU boundaries. Each boundary on its own come with a set of debug challenges that gets exponentially more difficult when you combine them. Even the fact that the AI tool is running on a macOS host and constantly has to talk to a Windows guest was the source of many wasted turns.
- Success can be hard to *quantify*. When Anthropic built their [C compiler](https://www.anthropic.com/engineering/building-c-compiler), they had a large corpus of inputs with a reference implementation to query in order to determine *correctness*. This kind of challenge can be brute forced by an LLM: try everything until the test passes. When building a graphics driver, you either need an existing collection of tests (such as the Vulkan CTS) or some A/B comparison of rendered frames. DirectX has some tests but they are no where near rich enough to build a driver just by observing test results.
- Failure can be hard to *quantify*. How will the AI know that every other frame is being dropped? How will the AI know that some elements are drawn incorrectly? How will the AI know that while everything is rendered correctly and no frames are dropped, the performance is 60% of what the hardware can achieve? These are all real problems that had to be solved.

All of these challenges are difficult for humans and they cannot be one-shotted by an AI assistant. Where the AI can help is to do the "grunt work" of trying out different designs, testing hypothesis, and building tools and harnesses for other agents. AI works the best autonomously when either the problem space is narrow or the success criteria is wide. AI tends to fall on its face when you have a large problem space with a narrow success criteria. When I hear about "impressive" work done by AI assistant without a skilled operator, it always falls into one or more of the following groups:
1. It is a visually impressive demo but not actually technically challenging. (Wide success criteria)
2. It heavily relies on existing work. (Narrow problem space)
3. It is not useful or working beyond the demo. (Both)

So what is the value of the human operator? Their job is to break a large and intractable problem into a series of smaller ones that is friendly for an AI to solve... and more importantly for AI to validate. Don't waste your time trying to prompt engineer or write skills or benchmark what the best coding harness is. All of that is table setting. The one skill you need to master is the same skill you needed before AI tools existed: the ability to break apart complex problems.

<div class="rpt rpt-assets">
<style>
/* ── Report components: adapted from the three generated analysis reports ── */
.rpt{
  /* neutral chrome mapped onto the blog palette */
  --page:#ffffff; --plane:#ffffff; --surface:#f6f7fb;
  --ink:#0b1020; --ink2:#5b6478; --muted:#8a92a5;
  --grid:#e5e8f0; --axis:#c8cddb; --hair:#e5e8f0; --rule:#e5e8f0;
  --wash:#eef2ff; --quote-bg:#f6f7fb;
  --shadow:0 1px 2px rgba(11,16,32,.04),0 8px 24px -14px rgba(11,16,32,.22);
  /* categorical series, carried over from the reports unchanged */
  --m1:#2a78d6; --m2:#eb6834; --m3:#1baf7a; --m4:#eda100; --m5:#e87ba4; --m6:#2c6b3a;
  --m0:#b0b6c6; --bad:#d1443c;
  --s1:#2a78d6; --s2:#eb6834; --s3:#1baf7a; --s4:#eda100;
  font-family:var(--font-sans);
  font-size:14.5px; line-height:1.6; color:var(--ink);
  font-feature-settings:"kern","liga";
  /* stay inside the article's reading measure */
  width:100%;
}
.rpt.rpt-assets{display:none}
@media (prefers-color-scheme:dark){
  .rpt{
    --page:#0b0f1e; --plane:#0b0f1e; --surface:#131829;
    --ink:#e8ebf4; --ink2:#969eb4; --muted:#6f7791;
    --grid:#1f2536; --axis:#2b3247; --hair:#1f2536; --rule:#1f2536;
    --wash:#182343; --quote-bg:#11162a;
    --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -14px rgba(0,0,0,.6);
    --m1:#3987e5; --m2:#d95926; --m3:#199e70; --m4:#c98500; --m5:#d55181; --m6:#4f9d63;
    --m0:#4a5265; --bad:#e05a52;
    --s1:#3987e5; --s2:#d95926; --s3:#199e70; --s4:#c98500;
  }
}
.rpt *,.rpt *::before,.rpt *::after{box-sizing:border-box}
.rpt p{margin:0 0 14px}
.rpt p:last-child{margin-bottom:0}
.rpt b,.rpt strong{font-weight:640;color:var(--ink);overflow-wrap:anywhere}
.rpt em{font-style:italic}
.rpt code{font-family:var(--font-mono);font-size:.87em;background:color-mix(in oklab,var(--ink) 7%,transparent);
  border:0;padding:1px 5px;border-radius:4px;color:inherit;overflow-wrap:anywhere}
.rpt svg{display:block;width:100%;height:auto;overflow:visible}
.rpt text{font-family:var(--font-sans)}
/* — section ledes sit at the reading measure, not the full breakout — */
.post-body .rpt-lede{color:var(--text-muted);font-size:1rem}
/* — stat tiles — */
.rpt .tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:0}
.rpt .tile{background:var(--surface);border:1px solid var(--hair);border-radius:10px;padding:14px 15px 12px}
.rpt .tile .tl,.rpt .tile .l{font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);font-weight:600;line-height:1.35}
.rpt .tile .l{text-transform:none;letter-spacing:0;font-size:12px;color:var(--ink2);margin-top:6px}
.rpt .tile .tv,.rpt .tile .v{font-size:26px;line-height:1.15;margin-top:4px;letter-spacing:-.02em;
  font-weight:650;font-variant-numeric:tabular-nums;color:var(--ink)}
.rpt .tile .v{margin-top:0}
.rpt .tile .ts,.rpt .tile .s{font-size:11.5px;color:var(--muted);margin-top:3px;line-height:1.4}
.rpt .tile.accent .tv{color:var(--m1)}
.rpt .tile.k .tv{color:var(--m5)} .rpt .tile.f .tv{color:var(--m3)} .rpt .tile.o .tv{color:var(--m1)}
/* — cards — */
.rpt .card{background:var(--surface);border:1px solid var(--hair);border-radius:12px;padding:20px 18px 16px}
.rpt .card + .card{margin-top:14px}
.rpt figure{margin:0;background:var(--surface);border:1px solid var(--hair);border-radius:12px;padding:20px 18px 16px}
.rpt figure .ftitle{font-size:15px;font-weight:650;letter-spacing:-.008em;margin:0 0 4px;color:var(--ink)}
.rpt figure .fsub{font-size:13px;color:var(--ink2);margin:0 0 18px;line-height:1.45}
.rpt figure figcaption{font-size:12px;color:var(--muted);margin-top:14px;padding-top:12px;
  border-top:1px solid var(--rule);line-height:1.5}
/* — chart chrome — */
.rpt .chart{width:100%;height:auto;display:block;overflow:visible}
/* day-by-day charts keep their designed density and pan sideways instead of shrinking */
.rpt .chart-scroll{overflow-x:auto;-webkit-overflow-scrolling:touch;padding-bottom:4px}
.rpt .chart-scroll svg{min-width:56rem}
.rpt .chart-scroll svg .tick,.rpt .chart-scroll svg .ax{font-size:13px}
.rpt .chart-scroll svg .month{font-size:13px}
.rpt .chart-scroll svg .dlabel{font-size:13.5px}
/* charts drawn on an 800-unit canvas scale ~0.65 to fit the column; compensate their type */
.rpt svg[viewBox^="0 0 800"] .tick,.rpt svg[viewBox^="0 0 800"] .ax{font-size:14px}
.rpt svg[viewBox^="0 0 800"] .lbl{font-size:15px}
.rpt svg[viewBox^="0 0 800"] .lbl-s{font-size:14.5px}
.rpt svg[viewBox^="0 0 800"] .val{font-size:15.5px}
.rpt svg[viewBox^="0 0 800"] .anno{font-size:14px}
.rpt .grid,.rpt .gridline{stroke:var(--grid);stroke-width:1}
.rpt .axis,.rpt .baseline{stroke:var(--axis);stroke-width:1}
.rpt .tick{fill:var(--muted);font-size:11px;font-variant-numeric:tabular-nums}
.rpt .ax{fill:var(--muted);font-size:11.5px}
.rpt .lbl{fill:var(--ink);font-size:12.5px}
.rpt .lbl-s{fill:var(--ink2);font-size:12px}
.rpt .val{fill:var(--ink);font-size:12.5px;font-weight:640}
.rpt .anno{fill:var(--ink2);font-size:11.5px}
.rpt .month,.rpt .alab{fill:var(--ink2);font-size:11.5px;font-weight:640;letter-spacing:.04em}
.rpt .dlabel{fill:var(--ink2);font-size:12px;font-weight:640;font-variant-numeric:tabular-nums}
.rpt .gapmark line{stroke:var(--grid);stroke-width:1}
.rpt .gapmark text{fill:var(--muted);font-size:10px}
.rpt .hit{fill:transparent}
.rpt .seg{transition:opacity .1s}
.rpt svg:hover .seg{opacity:.5}
.rpt svg .seg:hover,.rpt svg .seg.on{opacity:1}
.rpt .crv{fill:none;stroke-width:2.1;stroke-linejoin:round;stroke-linecap:round}
.rpt .dot{stroke:var(--surface);stroke-width:2}
.rpt .m1{fill:var(--m1)}.rpt .m2{fill:var(--m2)}.rpt .m3{fill:var(--m3)}.rpt .m4{fill:var(--m4)}
.rpt .m5{fill:var(--m5)}.rpt .m6{fill:var(--m6)}.rpt .m0{fill:var(--m0)}.rpt .cost{fill:var(--m1)}
/* — legends — */
.rpt .legend{display:flex;flex-wrap:wrap;gap:6px 20px;margin:14px 0 2px;font-size:12.5px;color:var(--ink2)}
.rpt .legend > span{display:inline-flex;align-items:center;gap:7px}
.rpt .lg{display:inline-flex;align-items:center;gap:7px}
/* a legend that is one long note, not a row of keys, reads as a paragraph */
.rpt .legend > .lg:only-child{display:block;line-height:1.55;max-width:88ch}
.rpt .lg b{font-weight:640;color:var(--ink);font-variant-numeric:tabular-nums}
.rpt .sw,.rpt .key{width:10px;height:10px;border-radius:3px;display:inline-block;flex:0 0 auto}
.rpt .sw.m1{background:var(--m1)}.rpt .sw.m2{background:var(--m2)}.rpt .sw.m3{background:var(--m3)}
.rpt .sw.m4{background:var(--m4)}.rpt .sw.m5{background:var(--m5)}.rpt .sw.m6{background:var(--m6)}
.rpt .sw.m0{background:var(--m0)}.rpt .sw.bad{background:var(--bad)}
.rpt .sw.k{background:var(--m5)}.rpt .sw.f{background:var(--m3)}.rpt .sw.o{background:var(--m1)}
.rpt .crv.k{stroke:var(--m5)}.rpt .crv.f{stroke:var(--m3)}.rpt .crv.o{stroke:var(--m1)}
/* — donut — */
.rpt .donut-wrap{display:flex;gap:32px;align-items:center;flex-wrap:wrap}
.rpt .donut{width:230px;flex:0 0 auto}
.rpt .donut-v{fill:var(--ink);font-size:25px;font-weight:640;letter-spacing:-.02em}
.rpt .donut-l{fill:var(--muted);font-size:11.5px}
.rpt .dlegend{list-style:none;margin:0;padding:0;flex:1 1 300px;min-width:260px}
.rpt .dlegend li{display:grid;grid-template-columns:14px 1fr auto auto;gap:12px;align-items:center;
  padding:7px 0;border-bottom:1px solid var(--hair);font-size:13.5px}
.rpt .dlegend li:last-child{border-bottom:0}
.rpt .dlegend .vl,.rpt .dlegend .pc{font-variant-numeric:tabular-nums;color:var(--ink2)}
.rpt .dlegend .pc{min-width:52px;text-align:right;color:var(--ink);font-weight:640}
/* — small multiples — */
.rpt .minis{display:grid;grid-template-columns:1fr;gap:18px 26px}
.rpt .mini{margin:0;background:none;border:0;padding:0}
.rpt .mini figcaption{display:flex;justify-content:space-between;align-items:baseline;
  font-size:13px;font-weight:640;margin:0 0 6px;color:var(--ink);border:0;padding:0}
.rpt .mini figcaption span{font-weight:400;color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}
/* — timeline — */
.rpt .timeline{list-style:none;margin:0;padding:0 0 0 30px;position:relative}
.rpt .timeline::before{content:"";position:absolute;left:5px;top:8px;bottom:8px;width:2px;
  background:var(--grid);border-radius:2px}
.rpt .tl-item{position:relative;margin:0 0 14px}
.rpt .tl-item + .tl-item,.rpt .timeline li + li{margin-top:0}
.rpt .tl-dot{position:absolute;left:-30px;top:20px;width:12px;height:12px;border-radius:50%;
  box-shadow:0 0 0 3px var(--page)}
.rpt .tl-dot.m1{background:var(--m1)}.rpt .tl-dot.m2{background:var(--m2)}.rpt .tl-dot.m3{background:var(--m3)}
.rpt .tl-dot.m4{background:var(--m4)}.rpt .tl-dot.m5{background:var(--m5)}.rpt .tl-dot.m6{background:var(--m6)}
.rpt .tl-dot.m0{background:var(--m0)}
.rpt .tl-card{background:var(--surface);border:1px solid var(--hair);border-radius:11px;padding:14px 16px 12px}
.rpt .tl-item.star .tl-card{border-color:color-mix(in oklab,var(--m1) 42%,var(--hair))}
.rpt .tl-date{font-size:11px;letter-spacing:.09em;text-transform:uppercase;color:var(--muted);font-weight:640}
.rpt .tl-card h3{margin:4px 0 6px;font-size:16.5px;letter-spacing:-.012em;font-weight:660;line-height:1.3;
  font-family:var(--font-sans);color:var(--ink)}
.rpt .tl-card h3 .star{font-style:normal;color:var(--m1);margin-right:7px}
.rpt .tl-card p{margin:0;color:var(--ink2);font-size:14px}
.rpt .chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:10px}
.rpt .chip{display:inline-flex;align-items:center;gap:6px;font-size:11.5px;color:var(--ink2);
  border:1px solid var(--hair);border-radius:999px;padding:2px 9px}
.rpt .chip b{font-weight:640;color:var(--ink);font-variant-numeric:tabular-nums}
.rpt .chip.mixed-chip{font-weight:640;color:var(--ink)}
.rpt .tl-gap{position:relative;margin:0 0 14px;padding:2px 0 10px}
.rpt .tl-gap span{font-size:12px;color:var(--muted);letter-spacing:.05em}
.rpt .tl-gap::before{content:"";position:absolute;left:-25px;top:6px;width:2px;height:12px;background:var(--page)}
/* — disclosure — */
.rpt details{margin:0}
.rpt details > summary{cursor:pointer;font-size:13px;color:var(--ink2);padding:8px 0;
  list-style:none;display:inline-flex;align-items:center;gap:8px}
.rpt details > summary::-webkit-details-marker{display:none}
.rpt details > summary::before{content:"▸";color:var(--muted);transition:transform .15s}
.rpt details[open] > summary::before{transform:rotate(90deg)}
.rpt details > summary:hover{color:var(--ink)}
.rpt details.tl-details > summary{font-size:14.5px;font-weight:640;color:var(--ink);
  background:var(--surface);border:1px solid var(--hair);border-radius:10px;padding:12px 16px;
  display:flex;width:100%}
.rpt details.tl-details > summary .sm{margin-left:auto;font-weight:400;color:var(--muted);font-size:12.5px}
.rpt details.tl-details[open] > summary{margin-bottom:20px}
/* — tables — */
.rpt .scroll,.rpt .tblwrap{overflow-x:auto;margin-top:6px;border:1px solid var(--hair);
  border-radius:10px;background:var(--surface)}
.rpt .dt,.rpt .tblwrap table{border-collapse:collapse;width:100%;font-size:12.5px;margin:0;min-width:520px}
.rpt .dt th,.rpt .dt td,.rpt .tblwrap th,.rpt .tblwrap td{padding:8px 13px;text-align:left;
  border-bottom:1px solid var(--hair);vertical-align:top;font-family:var(--font-sans)}
.rpt .dt td.n,.rpt .dt th.n,.rpt .tblwrap td.n,.rpt .tblwrap th.n{text-align:right;white-space:nowrap;
  font-variant-numeric:tabular-nums}
.rpt .dt thead th,.rpt .tblwrap thead th{color:var(--muted);font-weight:640;font-size:11px;letter-spacing:.05em;
  text-transform:uppercase;background:var(--surface);position:sticky;top:0}
.rpt .dt tbody th,.rpt .tblwrap tbody th{font-weight:500;color:var(--ink2)}
.rpt .dt thead th{min-width:7ch}
/* numeric headers may wrap so prose row-headers keep a readable measure */
.rpt .dt thead th.n,.rpt .tblwrap thead th.n{white-space:normal}
.rpt .dt tbody th{min-width:22ch}
.rpt .dt tfoot td,.rpt .dt tfoot th{border-bottom:0;border-top:1px solid var(--axis);font-weight:640;color:var(--ink)}
.rpt .dt tr.hi{background:color-mix(in oklab,var(--m1) 6%,transparent)}
.rpt .tblwrap .hi{color:var(--ink);font-weight:640}
.rpt .dt code,.rpt .tblwrap code{font-size:11.5px;overflow-wrap:anywhere}
.rpt .v{font-weight:700}
.rpt .v.y{color:var(--m3)} .rpt .v.p{color:var(--m4)} .rpt .v.n{color:var(--bad)}
.rpt .ax-n{font-size:11px}
.rpt .tblwrap .ax{fill:none;color:var(--muted);font-size:11.5px;font-weight:400}
/* turns-per-day table: numeric columns read better right-aligned and tight */
.rpt .dt.num td,.rpt .dt.num th{text-align:right;white-space:nowrap}
.rpt .dt.num tbody th,.rpt .dt.num tfoot th{text-align:left}
.rpt .dt.num tbody th .sw{margin-right:8px;vertical-align:-1px}
.rpt .dt.num td.tot{font-weight:640;color:var(--ink)}
/* — horizontal + stacked bar rows — */
.rpt .bars{list-style:none;margin:0;padding:0}
.rpt .bars li{display:grid;grid-template-columns:150px 1fr 84px;gap:12px;align-items:center;
  padding:6px 0;font-size:13px;margin:0}
.rpt .bars .nm{color:var(--ink2)}
.rpt .bars .tr{background:color-mix(in oklab,var(--ink) 7%,transparent);border-radius:5px;height:16px;
  position:relative;overflow:hidden}
.rpt .bars .fl{position:absolute;left:0;top:0;bottom:0;border-radius:5px}
.rpt .bars .fl.k{background:var(--m5)}.rpt .bars .fl.f{background:var(--m3)}.rpt .bars .fl.o{background:var(--m1)}
.rpt .bars .vv{text-align:right;font-variant-numeric:tabular-nums;font-weight:640;color:var(--ink)}
.rpt .stk{display:grid;grid-template-columns:150px 1fr 84px;gap:12px;align-items:center;padding:6px 0;font-size:13px}
.rpt .stk .tr{display:flex;height:18px;border-radius:5px;overflow:hidden;
  background:color-mix(in oklab,var(--ink) 7%,transparent)}
.rpt .stk .seg{height:100%}
.rpt .stk .nm{color:var(--ink2)}
.rpt .stk .vv{text-align:right;font-variant-numeric:tabular-nums;font-weight:640;color:var(--ink)}
/* — phase strip — */
.rpt .strip{margin:6px 0 0}
.rpt .strip .row{display:flex;height:30px;border-radius:7px;overflow:hidden;border:1px solid var(--hair)}
.rpt .strip .ph{display:grid;place-items:center;font-size:11.5px;font-weight:640;color:#fff;
  white-space:nowrap;overflow:hidden;padding:0 4px}
.rpt .strip .ticks{display:flex;justify-content:space-between;font-size:11px;color:var(--muted);
  margin-top:5px;font-variant-numeric:tabular-nums}
/* — design-lineage chain — */
.rpt .chain{list-style:none;margin:0;padding:0}
.rpt .chain li{display:grid;grid-template-columns:26px minmax(0,1fr);gap:14px;padding:0 0 16px;position:relative;margin:0}
.rpt .chain li::before{content:"";position:absolute;left:12px;top:26px;bottom:-2px;width:2px;background:var(--grid)}
.rpt .chain li:last-child{padding-bottom:0}
.rpt .chain li:last-child::before{display:none}
.rpt .chain .num{width:26px;height:26px;border-radius:50%;display:grid;place-items:center;
  font-size:12px;font-weight:700;color:#fff;background:var(--m0)}
.rpt .chain li.ok .num{background:var(--m3)} .rpt .chain li.no .num{background:var(--bad)}
.rpt .chain li.mid .num{background:var(--m4)}
.rpt .chain h4{margin:2px 0 4px;font-size:15px;font-weight:660;letter-spacing:-.01em;
  font-family:var(--font-sans);color:var(--ink)}
.rpt .chain p{margin:0;font-size:13.5px;color:var(--ink2)}
.rpt .chain .by{font-size:12px;color:var(--muted);margin-top:5px;display:block}
/* — verdict cards — */
.rpt .verdict{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px}
.rpt .verdict .card h4{margin:0 0 4px;font-size:16.5px;font-weight:670;letter-spacing:-.012em;
  font-family:var(--font-sans);color:var(--ink)}
.rpt .verdict .card .tagline{font-size:11.5px;letter-spacing:.07em;text-transform:uppercase;
  color:var(--muted);font-weight:640;margin:0 0 10px}
.rpt .verdict .card p{margin:0 0 10px;font-size:13.5px;color:var(--ink2)}
.rpt .verdict .card p:last-child{margin-bottom:0}
.rpt .verdict .card.k{border-top:3px solid var(--m5)}
.rpt .verdict .card.f{border-top:3px solid var(--m3)}
.rpt .verdict .card.o{border-top:3px solid var(--m1)}
/* — notes & callouts — */
.rpt .note p,.rpt .note li{font-size:13.5px;color:var(--ink2);max-width:76ch}
.rpt .note p{margin:0 0 10px}
.rpt .note ul,.rpt .note ol{padding-left:20px;margin:0 0 10px}
.rpt .note li{margin:6px 0}
.rpt ul,.rpt ol{margin:0 0 14px;padding-left:20px}
.rpt li{margin:5px 0}
.rpt .callout{border-left:3px solid var(--m1);padding:2px 0 2px 16px;margin:16px 0 0;
  color:var(--ink);font-size:14.5px;max-width:82ch}
.rpt .callout.warn{border-left-color:var(--m4)}
.rpt .callout.wash{border-left:0;background:var(--wash);border-radius:8px;padding:16px 18px;max-width:none}
.rpt .callout .h{font-size:11.5px;letter-spacing:.11em;text-transform:uppercase;color:var(--m1);
  font-weight:660;margin:0 0 6px}
@media (max-width:760px){
  .rpt .minis{grid-template-columns:1fr}
  .rpt .bars li,.rpt .stk{grid-template-columns:112px 1fr 68px;font-size:12px}
  .rpt .donut-wrap{gap:20px}
}
/* — prose carried over from the reports — */
.post-body h4{font-family:var(--font-serif);font-size:1.0625rem;font-weight:600;
  margin-top:1.9em;margin-bottom:.45em;letter-spacing:-.005em}
.post-body .lead{font-size:1.1875rem;line-height:1.6;color:var(--text-muted)}
.post-body .lede-prose{color:var(--text-muted)}
.post-body .rpt-byline{font-family:var(--font-sans);font-size:.8125rem;color:var(--text-faint);
  letter-spacing:.005em}
.post-body .rpt-note{font-family:var(--font-sans);font-size:.875rem;line-height:1.6;
  color:var(--text-faint);border-left:2px solid var(--border);padding-left:.9rem}
/* — transcript quotes reuse the blog's chat-snippet language — */
.post-body .quote-src{font-family:var(--font-sans);font-size:.78rem;letter-spacing:.03em;
  color:var(--text-faint);margin:.35rem 0 0 .2rem}
.post-body .exchange .quote-src{margin-bottom:.7rem}
.post-body .exchange .quote-src:last-child{margin-bottom:0}
.post-body .quote-src::before{content:"— "}
/* — chart tooltip (lives on <body>, outside .rpt) — */
#rpt-tip{position:fixed;left:0;top:0;pointer-events:none;opacity:0;transition:opacity .1s;z-index:60;
  background:#ffffff;border:1px solid #e5e8f0;border-radius:9px;padding:8px 11px;max-width:230px;
  box-shadow:0 1px 2px rgba(11,16,32,.06),0 10px 28px -12px rgba(11,16,32,.3);
  font-family:var(--font-sans);font-size:12.5px;line-height:1.45}
#rpt-tip .t1{color:#8a92a5;font-size:11px;letter-spacing:.05em;text-transform:uppercase;font-weight:640}
#rpt-tip .t2{color:#0b1020;font-weight:640}
#rpt-tip .t3{color:#5b6478;font-variant-numeric:tabular-nums}
@media (prefers-color-scheme:dark){
  #rpt-tip{background:#131829;border-color:#1f2536;box-shadow:0 1px 2px rgba(0,0,0,.5),0 10px 28px -12px rgba(0,0,0,.8)}
  #rpt-tip .t1{color:#6f7791}
  #rpt-tip .t2{color:#e8ebf4}
  #rpt-tip .t3{color:#969eb4}
}
</style>
<script>
(function(){
 if(document.getElementById('rpt-tip'))return;
 var tip=document.createElement('div');
 tip.id='rpt-tip';tip.setAttribute('role','status');tip.setAttribute('aria-live','polite');
 var a=document.createElement('div');a.className='t1';
 var b=document.createElement('div');b.className='t2';
 var c=document.createElement('div');c.className='t3';
 tip.appendChild(a);tip.appendChild(b);tip.appendChild(c);
 document.body.appendChild(tip);
 document.addEventListener('mousemove',function(e){
  var t=e.target&&e.target.closest?e.target.closest('[data-tip]'):null;
  if(!t){tip.style.opacity=0;return;}
  var p=t.getAttribute('data-tip').split('|');
  a.textContent=p[0]||'';b.textContent=p[1]||'';c.textContent=p[2]||'';
  tip.style.opacity=1;
  var r=tip.getBoundingClientRect(),x=e.clientX+14,y=e.clientY+14;
  if(x+r.width>innerWidth-8)x=e.clientX-r.width-14;
  if(y+r.height>innerHeight-8)y=e.clientY-r.height-14;
  tip.style.left=x+'px';tip.style.top=y+'px';
 },{passive:true});
})();
</script>
</div>

<h2>Forty days, on the record</h2>

The Triton bring-up started in late May, after the completion of the Neptune bring-up. There was a large break when Fable became unavailable because I had (correctly) hoped that it would be back soon (just not as soon as I had hoped).

<div class="rpt">
<div class="tiles"><div class="tile"><div class="tl">Sessions</div><div class="tv">208</div><div class="ts">183 with API turns</div></div><div class="tile"><div class="tl">User turns</div><div class="tv">2,178</div><div class="ts">40 active days</div></div><div class="tile"><div class="tl">API turns</div><div class="tv">51.9K</div><div class="ts">assistant messages</div></div><div class="tile"><div class="tl">Input tokens</div><div class="tv">4.18M</div><div class="ts">uncached</div></div><div class="tile"><div class="tl">Output tokens</div><div class="tv">67.4M</div><div class="ts">generated</div></div><div class="tile"><div class="tl">Cache read</div><div class="tv">18.3B</div><div class="ts">from prompt cache</div></div><div class="tile"><div class="tl">Cache write</div><div class="tv">233.9M</div><div class="ts">writes to prompt cache</div></div><div class="tile"><div class="tl">Subagent tokens</div><div class="tv">460.5M</div><div class="ts">included in totals</div></div><div class="tile accent"><div class="tl">Est. cost</div><div class="tv">$14,760</div><div class="ts">API pricing, June 2026</div></div></div>
</div>

<h3>The timeline</h3>

<p class="lede-prose">Each marker is coloured by the model that did the work; a split marker means the milestone spanned more than one model. Counts on the chips are user turns.</p>

<div class="rpt">
<details class="tl-details">
<summary>The full bring-up, milestone by milestone<span class="sm">33 entries · May 20 – Jul 23</span></summary>
<ol class="timeline"><li class="tl-item"><span class="tl-dot m2"></span><div class="tl-card"><div class="tl-date">May 20</div><h3>VirtualBox teardown → Triton is designed</h3><p>A study of how VirtualBox runs D3D11 in a VM (DDI → SVGA3D command stream → hypervisor → host D3D11) ends with the decision to collapse the middle two layers: <b>Triton</b> becomes a user-mode library that turns Windows D3D11 DDI calls straight back into D3D11 API calls, which Neptune already forwards to the host.</p><div class="chips"><span class="chip"><i class="sw m2"></i>Opus 4.7<b>18</b></span></div></div></li><li class="tl-item"><span class="tl-dot m2"></span><div class="tl-card"><div class="tl-date">May 20</div><h3>DDI surface and the DXBC container</h3><p>The DDI entry points get built out and inventoried. A first hallucinated <code>TritonDxbc</code> is thrown away and rewritten directly against VirtualBox’s <code>DevVGA-SVGA3d-dx-shader.cpp</code> — known-working code — with the chunking and command-encoding layers stripped out.</p><div class="chips"><span class="chip"><i class="sw m2"></i>Opus 4.7<b>32</b></span></div></div></li><li class="tl-item"><span class="tl-dot m2"></span><div class="tl-card"><div class="tl-date">May 22–23</div><h3>Windows KMD/UMD groundwork</h3><p>In parallel on the Windows and desktop machines: viogpu3d build automation, an ARM64 build port, patch triage across three diverged driver forks, and a variant analysis of the async-path fixes.</p><div class="chips"><span class="chip"><i class="sw m2"></i>Opus 4.7<b>188</b></span></div></div></li><li class="tl-item"><span class="tl-dot m2"></span><div class="tl-card"><div class="tl-date">May 24</div><h3>Every DDI cross-checked against MSDN</h3><p>A full review pass: each DDI function looked up on MSDN, compared against both the docs and the VirtualBox implementation, written up in <code>DDI_REVIEW.md</code>, then every finding independently re-validated and fixed. Followed by a licensing, naming and comment cleanup.</p><div class="chips"><span class="chip"><i class="sw m2"></i>Opus 4.7<b>20</b></span></div></div></li><li class="tl-item"><span class="tl-dot m2"></span><div class="tl-card"><div class="tl-date">May 25</div><h3>Neptune wired into the Windows build</h3><p>virtio-win-mesa (UMD) + viogpu3d (KMD) + neptune-protocol all building on the Windows dev VM, and a two-VM development loop stood up on the Linux box: dev VM builds, test VM runs under <code>-snapshot</code>, WinDbg over COM2, artifacts shared through virtiofs <code>Z:\</code>.</p><div class="chips"><span class="chip"><i class="sw m2"></i>Opus 4.7<b>41</b></span></div></div></li><li class="tl-item"><span class="tl-dot m2"></span><div class="tl-card"><div class="tl-date">May 26–28</div><h3>Present path lands — and a TDR loop blocks the desktop</h3><p>The DXGI present proposal is implemented on both sides and verified (<code>FlushToScreen scanout blob valid=1 1920x1080</code>, 54 clean swapchains). The desktop still doesn’t come up: a TDR → bugcheck → reboot loop is root-caused to an unregistered shader-resource view tearing down the context — a pre-existing DXVK shared-resource bug.</p><div class="chips"><span class="chip"><i class="sw m2"></i>Opus 4.7<b>41</b></span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>6</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">May 28 – Jul 1</div><h3>Guest-side shared handles</h3><p>Neither DXVK nor the future backends can pass shared handles through, so they get emulated on the guest using the fence and context-blob machinery already in place. The session runs across the four-week gap; it ends by proving the live desktop capture works and cleanly <em>dis</em>proving app-liveness via draw-RT capture — DWM layers app windows through DirectComposition, invisible to the render server.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>71</b></span></div></div></li><li class="tl-gap"><span>6 days quiet</span></li><li class="tl-item"><span class="tl-dot m2"></span><div class="tl-card"><div class="tl-date">Jun 4–5</div><h3>DXGI DDI study</h3><p>The two virtualization drivers’ DXGI swapchain DDIs put side by side — Neptune’s WIP implementation against VirtualBox’s — to settle the architectural questions before the rework.</p><div class="chips"><span class="chip"><i class="sw m2"></i>Opus 4.7<b>17</b></span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>3</b></span></div></div></li><li class="tl-gap"><span>5 days quiet</span></li><li class="tl-item"><span class="tl-dot m3"></span><div class="tl-card"><div class="tl-date">Jun 10</div><h3>d3dmetal-native begun</h3><p><code>libd3dmetal-native</code> starts on the laptop: a native macOS library implementing the GFXT interface on top of Apple’s D3DMetal.framework — essentially dxvk-native but backed by Metal. It becomes the macOS host renderer that Triton talks to two weeks later.</p><div class="chips"><span class="chip"><i class="sw m3"></i>Fable 5<b>5</b></span></div></div></li><li class="tl-gap"><span>20 days quiet</span></li><li class="tl-item"><span class="tl-dot m3"></span><div class="tl-card"><div class="tl-date">Jul 1</div><h3>Clean-slate re-bring-up</h3><p>Everything the previous agent had stashed stays stashed. A fresh context re-reads Neptune, Triton, KMD and UMD from scratch, reviews before writing, and rebuilds the whole host and guest stack. Part of that pass was confirming that <b>no VirtualBox code remains in the Triton driver</b> — VirtualBox stays a behavioural reference only, consulted for what a correct DDI implementation has to do (the &ldquo;VBox-parity&rdquo; DDI surface, and the find that <code>SetDisplayMode</code> was a silent stub), never a source of code.</p><div class="chips"><span class="chip"><i class="sw m3"></i>Fable 5<b>8</b></span></div></div></li><li class="tl-item star"><span class="tl-dot m3"></span><div class="tl-card"><div class="tl-date">Jul 2</div><h3><i class='star'>★</i>The Windows desktop renders</h3><p><b>Live desktop up in the QEMU window</b> — user Active, presents flowing, zero errors. The last two crashes go with it: a KMD blob-info race (fixed with a locked snapshot + degenerate-scanout deferral) and a QEMU <code>qemu_memfd_alloc</code> abort, now structurally impossible via scanout-blob rect validation.</p><div class="chips"><span class="chip"><i class="sw m3"></i>Fable 5<b>8</b></span></div></div></li><li class="tl-item"><span class="tl-dot mixed" style="background:conic-gradient(from -90deg,var(--m3) 0.0%,var(--m3) 72.0%,var(--m1) 72.0%,var(--m1) 100.0%)"></span><div class="tl-card"><div class="tl-date">Jul 2–3</div><h3>dmabuf replaces the fake shared handles</h3><p>The emulated handles come out. DXVK gets real dmabuf import/export, and virglrenderer and guest Mesa drop the single-host-device / threaded-context sharing hack.</p><div class="chips"><span class="chip mixed-chip">Mixed</span><span class="chip"><i class="sw m3"></i>Fable 5<b>18</b></span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>7</b></span></div></div></li><li class="tl-item"><span class="tl-dot m3"></span><div class="tl-card"><div class="tl-date">Jul 3</div><h3>Artifact triage: glyphs, icons, compositing</h3><p>With the desktop up, the rendering is wrong in interesting ways — wrong glyphs, half-noise icons, fully transparent windows with working title bars. The first job is a way to diagnose it without a human looking at screenshots.</p><div class="chips"><span class="chip"><i class="sw m3"></i>Fable 5<b>23</b></span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>4</b></span></div></div></li><li class="tl-item star"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 4</div><h3><i class='star'>★</i>Fire Strike runs to completion</h3><p>A full 3DMark Fire Strike run finishes <code>EXIT 0</code> with real scores (Graphics 1347 / Physics 1858 / Combined 369), rendering live to the GTK window — Demo and GT1 playing fullscreen with FlushToScreen past 900 presents.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>10</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 5</div><h3>Neptune on macOS: the cube spins</h3><p>The other front: Neptune ported to macOS over d3dmetal-native, running under Wine + FEX in QEMU. First green run — 3,603 presents, zero crashes — after gating the Venus ring watchdog on CPUID emulator detection.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>26</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 6</div><h3>The perf ceiling is not the driver</h3><p>Fire Strike GT1 is pinned at ~8 FPS and every driver-side lever moves it by nothing — which is the proof. GPU 99% busy at 300 MHz, package power 4 W of 50 W: a <code>30-amdgpu-pm.rules</code> udev clamp forcing <code>power_dpm_force_performance_level=low</code> on every boot. The &gt;5000 goal was unreachable, with receipts.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>28</b></span><span class="chip"><i class="sw m3"></i>Fable 5<b>5</b></span></div></div></li><li class="tl-item"><span class="tl-dot mixed" style="background:conic-gradient(from -90deg,var(--m1) 0.0%,var(--m1) 69.2%,var(--m3) 69.2%,var(--m3) 100.0%)"></span><div class="tl-card"><div class="tl-date">Jul 6</div><h3>Stability: ten clean cycles</h3><p>Ten consecutive boot → install driver → Fire Strike → screenshot → calc.exe → screenshot cycles, plus the fix for a long-standing wedge where the GTK window froze right after driver install.</p><div class="chips"><span class="chip mixed-chip">Mixed</span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>9</b></span><span class="chip"><i class="sw m3"></i>Fable 5<b>4</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 6–8</div><h3>WSI moves to the guest; repos cleaned for upstream</h3><p>Host-side swapchain creation is removed entirely — the guest driver owns swapchain management and shares textures for scanout. virglrenderer, Mesa and DXVK histories are rewritten, diagnostics stripped, and the whole stack re-tested end to end.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>91</b></span><span class="chip"><i class="sw m3"></i>Fable 5<b>5</b></span></div></div></li><li class="tl-item"><span class="tl-dot mixed" style="background:conic-gradient(from -90deg,var(--m1) 0.0%,var(--m1) 59.3%,var(--m3) 59.3%,var(--m3) 100.0%)"></span><div class="tl-card"><div class="tl-date">Jul 9</div><h3>Windows-on-ARM bring-up starts on Apple silicon</h3><p>The desktop machine takes over: Windows on ARM64 under QEMU on macOS, Triton talking to d3dmetal-native on the host, KDNet debugging into a Windows dev machine over SSH. Nothing renders yet.</p><div class="chips"><span class="chip mixed-chip">Mixed</span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>16</b></span><span class="chip"><i class="sw m3"></i>Fable 5<b>11</b></span></div></div></li><li class="tl-item star"><span class="tl-dot mixed" style="background:conic-gradient(from -90deg,var(--m1) 0.0%,var(--m1) 72.9%,var(--m3) 72.9%,var(--m3) 100.0%)"></span><div class="tl-card"><div class="tl-date">Jul 10</div><h3><i class='star'>★</i>Desktop, taskbar and GDI apps render on ARM64</h3><p>Five root fixes land: the DXBC converter SIGSEGV (ISGN scalar-mask widening), a KMD paging bugcheck, a GPU-residency wedge, vrend↔neptune shared-memory aliasing (which unblocked all window content), and host-side A8→RGBA8 translation for DWM’s glyph atlas. regedit is pixel-perfect; GPU-drawn glyphs are still wrong.</p><div class="chips"><span class="chip mixed-chip">Mixed</span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>43</b></span><span class="chip"><i class="sw m3"></i>Fable 5<b>16</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 12</div><h3>Fire Strike perf pass on Apple silicon</h3><p>Fire Strike made to launch, then profiled on both sides of the boundary — guest KMD/UMD and host render server — with symbols resolved, until the workload is GPU-bound.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>31</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 13</div><h3>A blank-frame detector in the host</h3><p>Every few frames come back solid black or a flat color. Rather than eyeball screenshots, the host maps the first page of each frame and samples ~1024 pixels, so the bug can be reproduced and counted automatically.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>77</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 14–16</div><h3>The colour/RG-swap hunt</h3><p>Fire Strike’s demo tints red or green and GT1’s particle effects come out the wrong colour — green flames. The hunt runs through Triton’s workaround code and D3DMetal-native.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>38</b></span><span class="chip"><i class="sw m3"></i>Fable 5<b>8</b></span></div></div></li><li class="tl-item"><span class="tl-dot m3"></span><div class="tl-card"><div class="tl-date">Jul 15</div><h3>DXBC container review finds the miscompile class</h3><p>A review of Triton’s DXBC container implementation against VirtualBox’s translator and the other reference implementations, aimed at the subtle shaper bug that makes the host translator miscompile some shaders.</p><div class="chips"><span class="chip"><i class="sw m3"></i>Fable 5<b>5</b></span></div></div></li><li class="tl-item"><span class="tl-dot mixed" style="background:conic-gradient(from -90deg,var(--m1) 0.0%,var(--m1) 57.7%,var(--m3) 57.7%,var(--m3) 100.0%)"></span><div class="tl-card"><div class="tl-date">Jul 16</div><h3>DXMT added as a second macOS backend</h3><p>dxmt-native gets fence and texture export/import over shmem and is wired into virglrenderer alongside d3dmetal-native — and unlike D3DMetal it builds native ARM64, no Rosetta. Linux + Wine validates first, then Triton + Windows.</p><div class="chips"><span class="chip mixed-chip">Mixed</span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>15</b></span><span class="chip"><i class="sw m3"></i>Fable 5<b>11</b></span></div></div></li><li class="tl-item star"><span class="tl-dot mixed" style="background:conic-gradient(from -90deg,var(--m1) 0.0%,var(--m1) 60.9%,var(--m3) 60.9%,var(--m3) 100.0%)"></span><div class="tl-card"><div class="tl-date">Jul 17</div><h3><i class='star'>★</i>Fire Strike to completion on refactored DXMT</h3><p>The refactored DXMT renders Fire Strike to completion at <b>4989</b> (Graphics 6213 / Physics 5068 / Combined 1995) on the fast host — confirmed against the exact HEAD build, with the earlier &ldquo;renders nothing&rdquo; shown to be intermittent rather than a break in the refactor.</p><div class="chips"><span class="chip mixed-chip">Mixed</span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>14</b></span><span class="chip"><i class="sw m3"></i>Fable 5<b>9</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 17</div><h3>arm64x packaging</h3><p>The Triton UMD is packaged as arm64x — arm64ec and x64 in one binary — through a dedicated build step rather than out-of-band scripts, the KMD gains a user service, and a full build-and-test cycle runs against both host backends.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>72</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 18</div><h3>DWM layer drops traced to the impostor texture</h3><p>Windowed apps lose whole composition layers on D3DMetal-native — empty start menus, missing search boxes, borderless windows. The trail leads into <code>substitute()</code>, where shmem-backed impostor textures stand in for shared textures so they can cross process boundaries.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>42</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 19</div><h3>Device-lost and black-screen hangs fixed</h3><p>Two black-screen variants — immediately after driver install, and after a complete Fire Strike session — chased through KDNet, guest and host tooling; plus an audit of the impostor-texture mechanism against Apple’s docs.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>99</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 20</div><h3>History collapsed to one Triton commit</h3><p>Upstream prep: every follow-up commit that belongs to Triton is rolled into a single introducing commit, with Neptune-side and unrelated changes kept separate. Performance characterisation of the D3DMetal-native path begins.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>57</b></span></div></div></li><li class="tl-item"><span class="tl-dot m1"></span><div class="tl-card"><div class="tl-date">Jul 21–22</div><h3>Present-gate pipelining</h3><p>Present was blocking on GPU work, leaving both CPU and GPU under-utilised. Unblocking it let presents race ahead into black frames; the fix moves the gate out of the UMD DDI and onto the KMD mechanism designed for it.</p><div class="chips"><span class="chip"><i class="sw m1"></i>Opus 4.8<b>70</b></span><span class="chip"><i class="sw m5"></i>Kimi K3<b>16</b></span><span class="chip"><i class="sw m6"></i>Sonnet 5<b>7</b></span></div></div></li><li class="tl-item star"><span class="tl-dot m3"></span><div class="tl-card"><div class="tl-date">Jul 23</div><h3><i class='star'>★</i>Final numbers</h3><p>Back-to-back clean Fire Strike runs on the Windows guest: <b>5124</b> on DXMT (ARM64) and <b>5682</b> on D3DMetal (x86_64/Rosetta), all four workloads, <code>EXITCODE=0</code>, black-frame rate ≤0.8%. The Linux/Wine reference on the same host scores <b>7624</b>.</p><div class="chips"><span class="chip"><i class="sw m3"></i>Fable 5<b>54</b></span><span class="chip"><i class="sw m1"></i>Opus 4.8<b>6</b></span></div></div></li><li class="tl-item"><span class="tl-dot m3"></span><div class="tl-card"><div class="tl-date">Jul 23</div><h3>Upstream review pass over UMD and KMD</h3><p>Interactive, item-by-item review of the guest driver code — development narratives out of the comments, bring-up log entries accounted for, MSDN contracts re-checked — ahead of publication.</p><div class="chips"><span class="chip"><i class="sw m3"></i>Fable 5<b>16</b></span></div></div></li></ol>
</details>
</div>

<h3>User turns per day</h3>

<div class="rpt wide">
<div class="card">
    <div class="chart-scroll"><svg class="chart" viewBox="0 0 1180 300" preserveAspectRatio="xMidYMid meet" role="img" aria-label="User turns per day, split by model"><line class="grid" x1="52" x2="1166" y1="254.0" y2="254.0"/><text class="tick" x="43" y="257.5" text-anchor="end">0</text><line class="grid" x1="52" x2="1166" y1="194.5" y2="194.5"/><text class="tick" x="43" y="198.0" text-anchor="end">50</text><line class="grid" x1="52" x2="1166" y1="135.0" y2="135.0"/><text class="tick" x="43" y="138.5" text-anchor="end">100</text><line class="grid" x1="52" x2="1166" y1="75.5" y2="75.5"/><text class="tick" x="43" y="79.0" text-anchor="end">150</text><line class="grid" x1="52" x2="1166" y1="16.0" y2="16.0"/><text class="tick" x="43" y="19.5" text-anchor="end">200</text><line class="axis" x1="52" x2="1166" y1="254" y2="254"/><rect class="seg m2" x="55.9" y="180.2" width="16.5" height="71.8" rx="3" data-tip="2026-05-20|Opus 4.7|62 turns of 62"/><rect class="hit" x="52.0" y="16" width="24.2" height="238" data-tip="2026-05-20|Total|62 user turns"/><text class="tick" x="64.1" y="269" text-anchor="middle">20</text><text class="month" x="64.1" y="286" text-anchor="middle">May</text><rect class="seg m2" x="80.1" y="245.7" width="16.5" height="6.3" rx="3" data-tip="2026-05-21|Opus 4.7|7 turns of 12"/><rect class="seg m0" x="80.1" y="239.7" width="16.5" height="4.0" rx="0" data-tip="2026-05-21|No reply|5 turns of 12"/><rect class="hit" x="76.2" y="16" width="24.2" height="238" data-tip="2026-05-21|Total|12 user turns"/><text class="tick" x="88.3" y="269" text-anchor="middle">21</text><rect class="seg m2" x="104.3" y="55.3" width="16.5" height="196.7" rx="3" data-tip="2026-05-22|Opus 4.7|167 turns of 167"/><rect class="hit" x="100.4" y="16" width="24.2" height="238" data-tip="2026-05-22|Total|167 user turns"/><text class="tick" x="112.5" y="269" text-anchor="middle">22</text><rect class="seg m2" x="128.5" y="202.8" width="16.5" height="49.2" rx="3" data-tip="2026-05-23|Opus 4.7|43 turns of 43"/><rect class="hit" x="124.7" y="16" width="24.2" height="238" data-tip="2026-05-23|Total|43 user turns"/><text class="tick" x="136.8" y="269" text-anchor="middle">23</text><rect class="seg m2" x="152.7" y="223.1" width="16.5" height="28.9" rx="3" data-tip="2026-05-24|Opus 4.7|26 turns of 26"/><rect class="hit" x="148.9" y="16" width="24.2" height="238" data-tip="2026-05-24|Total|26 user turns"/><text class="tick" x="161.0" y="269" text-anchor="middle">24</text><rect class="seg m2" x="177.0" y="210.0" width="16.5" height="42.0" rx="3" data-tip="2026-05-25|Opus 4.7|37 turns of 37"/><rect class="hit" x="173.1" y="16" width="24.2" height="238" data-tip="2026-05-25|Total|37 user turns"/><text class="tick" x="185.2" y="269" text-anchor="middle">25</text><rect class="seg m2" x="201.2" y="226.6" width="16.5" height="25.4" rx="3" data-tip="2026-05-26|Opus 4.7|23 turns of 23"/><rect class="hit" x="197.3" y="16" width="24.2" height="238" data-tip="2026-05-26|Total|23 user turns"/><text class="tick" x="209.4" y="269" text-anchor="middle">26</text><rect class="seg m2" x="225.4" y="217.1" width="16.5" height="34.9" rx="3" data-tip="2026-05-27|Opus 4.7|31 turns of 32"/><rect class="seg m0" x="225.4" y="215.9" width="16.5" height="0.8" rx="0" data-tip="2026-05-27|No reply|1 turn of 32"/><rect class="hit" x="221.5" y="16" width="24.2" height="238" data-tip="2026-05-27|Total|32 user turns"/><text class="tick" x="233.6" y="269" text-anchor="middle">27</text><rect class="seg m1" x="249.6" y="239.7" width="16.5" height="12.3" rx="3" data-tip="2026-05-28|Opus 4.8|12 turns of 18"/><rect class="seg m2" x="249.6" y="232.6" width="16.5" height="5.1" rx="0" data-tip="2026-05-28|Opus 4.7|6 turns of 18"/><rect class="hit" x="245.7" y="16" width="24.2" height="238" data-tip="2026-05-28|Total|18 user turns"/><text class="tick" x="257.8" y="269" text-anchor="middle">28</text><rect class="seg m1" x="273.8" y="218.3" width="16.5" height="33.7" rx="3" data-tip="2026-05-29|Opus 4.8|30 turns of 30"/><rect class="hit" x="270.0" y="16" width="24.2" height="238" data-tip="2026-05-29|Total|30 user turns"/><text class="tick" x="282.1" y="269" text-anchor="middle">29</text><rect class="seg m1" x="298.0" y="244.5" width="16.5" height="7.5" rx="3" data-tip="2026-05-30|Opus 4.8|8 turns of 9"/><rect class="seg m2" x="298.0" y="243.3" width="16.5" height="0.8" rx="0" data-tip="2026-05-30|Opus 4.7|1 turn of 9"/><rect class="hit" x="294.2" y="16" width="24.2" height="238" data-tip="2026-05-30|Total|9 user turns"/><text class="tick" x="306.3" y="269" text-anchor="middle">30</text><g class="gapmark"><line x1="354.7" x2="354.7" y1="22" y2="254"/><text x="354.7" y="269" text-anchor="middle">4d</text></g><rect class="seg m1" x="370.7" y="250.4" width="16.5" height="1.6" rx="3" data-tip="2026-06-04|Opus 4.8|3 turns of 10"/><rect class="seg m2" x="370.7" y="242.1" width="16.5" height="6.3" rx="0" data-tip="2026-06-04|Opus 4.7|7 turns of 10"/><rect class="hit" x="366.8" y="16" width="24.2" height="238" data-tip="2026-06-04|Total|10 user turns"/><text class="tick" x="378.9" y="269" text-anchor="middle">4</text><text class="month" x="378.9" y="286" text-anchor="middle">Jun</text><rect class="seg m2" x="394.9" y="242.1" width="16.5" height="9.9" rx="3" data-tip="2026-06-05|Opus 4.7|10 turns of 10"/><rect class="hit" x="391.0" y="16" width="24.2" height="238" data-tip="2026-06-05|Total|10 user turns"/><text class="tick" x="403.2" y="269" text-anchor="middle">5</text><g class="gapmark"><line x1="451.6" x2="451.6" y1="22" y2="254"/><text x="451.6" y="269" text-anchor="middle">4d</text></g><rect class="seg m3" x="467.6" y="248.1" width="16.5" height="4.0" rx="3" data-tip="2026-06-10|Fable 5|5 turns of 6"/><rect class="seg m0" x="467.6" y="246.9" width="16.5" height="0.8" rx="0" data-tip="2026-06-10|No reply|1 turn of 6"/><rect class="hit" x="463.7" y="16" width="24.2" height="238" data-tip="2026-06-10|Total|6 user turns"/><text class="tick" x="475.8" y="269" text-anchor="middle">10</text><g class="gapmark"><line x1="524.2" x2="524.2" y1="22" y2="254"/><text x="524.2" y="269" text-anchor="middle">17d</text></g><rect class="seg m1" x="540.2" y="237.3" width="16.5" height="14.7" rx="3" data-tip="2026-06-28|Opus 4.8|14 turns of 14"/><rect class="hit" x="536.3" y="16" width="24.2" height="238" data-tip="2026-06-28|Total|14 user turns"/><text class="tick" x="548.5" y="269" text-anchor="middle">28</text><rect class="seg m1" x="564.4" y="240.9" width="16.5" height="11.1" rx="3" data-tip="2026-06-29|Opus 4.8|11 turns of 11"/><rect class="hit" x="560.6" y="16" width="24.2" height="238" data-tip="2026-06-29|Total|11 user turns"/><text class="tick" x="572.7" y="269" text-anchor="middle">29</text><rect class="seg m1" x="588.7" y="244.5" width="16.5" height="7.5" rx="3" data-tip="2026-06-30|Opus 4.8|8 turns of 8"/><rect class="hit" x="584.8" y="16" width="24.2" height="238" data-tip="2026-06-30|Total|8 user turns"/><text class="tick" x="596.9" y="269" text-anchor="middle">30</text><rect class="seg m1" x="612.9" y="236.2" width="16.5" height="15.9" rx="3" data-tip="2026-07-01|Opus 4.8|15 turns of 33"/><rect class="seg m3" x="612.9" y="230.2" width="16.5" height="4.0" rx="0" data-tip="2026-07-01|Fable 5|5 turns of 33"/><rect class="seg m0" x="612.9" y="214.7" width="16.5" height="13.5" rx="0" data-tip="2026-07-01|No reply|13 turns of 33"/><rect class="hit" x="609.0" y="16" width="24.2" height="238" data-tip="2026-07-01|Total|33 user turns"/><text class="tick" x="621.1" y="269" text-anchor="middle">1</text><text class="month" x="621.1" y="286" text-anchor="middle">Jul</text><rect class="seg m1" x="637.1" y="225.4" width="16.5" height="26.6" rx="3" data-tip="2026-07-02|Opus 4.8|24 turns of 52"/><rect class="seg m3" x="637.1" y="192.1" width="16.5" height="31.3" rx="0" data-tip="2026-07-02|Fable 5|28 turns of 52"/><rect class="hit" x="633.2" y="16" width="24.2" height="238" data-tip="2026-07-02|Total|52 user turns"/><text class="tick" x="645.3" y="269" text-anchor="middle">2</text><rect class="seg m1" x="661.3" y="242.1" width="16.5" height="9.9" rx="3" data-tip="2026-07-03|Opus 4.8|10 turns of 65"/><rect class="seg m3" x="661.3" y="176.6" width="16.5" height="63.5" rx="0" data-tip="2026-07-03|Fable 5|55 turns of 65"/><rect class="hit" x="657.4" y="16" width="24.2" height="238" data-tip="2026-07-03|Total|65 user turns"/><text class="tick" x="669.5" y="269" text-anchor="middle">3</text><rect class="seg m1" x="685.5" y="224.2" width="16.5" height="27.8" rx="3" data-tip="2026-07-04|Opus 4.8|25 turns of 50"/><rect class="seg m3" x="685.5" y="194.5" width="16.5" height="27.8" rx="0" data-tip="2026-07-04|Fable 5|25 turns of 50"/><rect class="hit" x="681.7" y="16" width="24.2" height="238" data-tip="2026-07-04|Total|50 user turns"/><text class="tick" x="693.8" y="269" text-anchor="middle">4</text><rect class="seg m1" x="709.7" y="185.0" width="16.5" height="67.0" rx="3" data-tip="2026-07-05|Opus 4.8|58 turns of 59"/><rect class="seg m0" x="709.7" y="183.8" width="16.5" height="0.8" rx="0" data-tip="2026-07-05|No reply|1 turn of 59"/><rect class="hit" x="705.9" y="16" width="24.2" height="238" data-tip="2026-07-05|Total|59 user turns"/><text class="tick" x="718.0" y="269" text-anchor="middle">5</text><rect class="seg m1" x="734.0" y="95.7" width="16.5" height="156.3" rx="3" data-tip="2026-07-06|Opus 4.8|133 turns of 146"/><rect class="seg m3" x="734.0" y="80.3" width="16.5" height="13.5" rx="0" data-tip="2026-07-06|Fable 5|13 turns of 146"/><rect class="hit" x="730.1" y="16" width="24.2" height="238" data-tip="2026-07-06|Total|146 user turns"/><text class="tick" x="742.2" y="269" text-anchor="middle">6</text><rect class="seg m1" x="758.2" y="188.6" width="16.5" height="63.5" rx="3" data-tip="2026-07-07|Opus 4.8|55 turns of 56"/><rect class="seg m3" x="758.2" y="187.4" width="16.5" height="0.8" rx="0" data-tip="2026-07-07|Fable 5|1 turn of 56"/><rect class="hit" x="754.3" y="16" width="24.2" height="238" data-tip="2026-07-07|Total|56 user turns"/><text class="tick" x="766.4" y="269" text-anchor="middle">7</text><rect class="seg m1" x="782.4" y="183.8" width="16.5" height="68.2" rx="3" data-tip="2026-07-08|Opus 4.8|59 turns of 62"/><rect class="seg m2" x="782.4" y="180.2" width="16.5" height="1.6" rx="0" data-tip="2026-07-08|Opus 4.7|3 turns of 62"/><rect class="hit" x="778.5" y="16" width="24.2" height="238" data-tip="2026-07-08|Total|62 user turns"/><text class="tick" x="790.6" y="269" text-anchor="middle">8</text><rect class="seg m1" x="806.6" y="190.9" width="16.5" height="61.1" rx="3" data-tip="2026-07-09|Opus 4.8|53 turns of 86"/><rect class="seg m2" x="806.6" y="189.7" width="16.5" height="0.8" rx="0" data-tip="2026-07-09|Opus 4.7|1 turn of 86"/><rect class="seg m3" x="806.6" y="155.2" width="16.5" height="32.5" rx="0" data-tip="2026-07-09|Fable 5|29 turns of 86"/><rect class="seg m0" x="806.6" y="151.7" width="16.5" height="1.6" rx="0" data-tip="2026-07-09|No reply|3 turns of 86"/><rect class="hit" x="802.7" y="16" width="24.2" height="238" data-tip="2026-07-09|Total|86 user turns"/><text class="tick" x="814.8" y="269" text-anchor="middle">9</text><rect class="seg m1" x="830.8" y="250.4" width="16.5" height="1.6" rx="3" data-tip="2026-07-10|Opus 4.8|3 turns of 14"/><rect class="seg m3" x="830.8" y="237.3" width="16.5" height="11.1" rx="0" data-tip="2026-07-10|Fable 5|11 turns of 14"/><rect class="hit" x="827.0" y="16" width="24.2" height="238" data-tip="2026-07-10|Total|14 user turns"/><text class="tick" x="839.1" y="269" text-anchor="middle">10</text><rect class="seg m1" x="855.0" y="240.9" width="16.5" height="11.1" rx="3" data-tip="2026-07-11|Opus 4.8|11 turns of 14"/><rect class="seg m3" x="855.0" y="237.3" width="16.5" height="1.6" rx="0" data-tip="2026-07-11|Fable 5|3 turns of 14"/><rect class="hit" x="851.2" y="16" width="24.2" height="238" data-tip="2026-07-11|Total|14 user turns"/><text class="tick" x="863.3" y="269" text-anchor="middle">11</text><rect class="seg m1" x="879.3" y="138.6" width="16.5" height="113.4" rx="3" data-tip="2026-07-12|Opus 4.8|97 turns of 99"/><rect class="seg m0" x="879.3" y="136.2" width="16.5" height="0.8" rx="0" data-tip="2026-07-12|No reply|2 turns of 99"/><rect class="hit" x="875.4" y="16" width="24.2" height="238" data-tip="2026-07-12|Total|99 user turns"/><text class="tick" x="887.5" y="269" text-anchor="middle">12</text><rect class="seg m1" x="903.5" y="180.2" width="16.5" height="71.8" rx="3" data-tip="2026-07-13|Opus 4.8|62 turns of 62"/><rect class="hit" x="899.6" y="16" width="24.2" height="238" data-tip="2026-07-13|Total|62 user turns"/><text class="tick" x="911.7" y="269" text-anchor="middle">13</text><rect class="seg m1" x="927.7" y="199.3" width="16.5" height="52.7" rx="3" data-tip="2026-07-14|Opus 4.8|46 turns of 49"/><rect class="seg m0" x="927.7" y="195.7" width="16.5" height="1.6" rx="0" data-tip="2026-07-14|No reply|3 turns of 49"/><rect class="hit" x="923.8" y="16" width="24.2" height="238" data-tip="2026-07-14|Total|49 user turns"/><text class="tick" x="935.9" y="269" text-anchor="middle">14</text><rect class="seg m1" x="951.9" y="217.1" width="16.5" height="34.9" rx="3" data-tip="2026-07-15|Opus 4.8|31 turns of 33"/><rect class="seg m3" x="951.9" y="214.7" width="16.5" height="0.8" rx="0" data-tip="2026-07-15|Fable 5|2 turns of 33"/><rect class="hit" x="948.0" y="16" width="24.2" height="238" data-tip="2026-07-15|Total|33 user turns"/><text class="tick" x="960.2" y="269" text-anchor="middle">15</text><rect class="seg m1" x="976.1" y="248.1" width="16.5" height="4.0" rx="3" data-tip="2026-07-16|Opus 4.8|5 turns of 27"/><rect class="seg m3" x="976.1" y="221.9" width="16.5" height="24.2" rx="0" data-tip="2026-07-16|Fable 5|22 turns of 27"/><rect class="hit" x="972.3" y="16" width="24.2" height="238" data-tip="2026-07-16|Total|27 user turns"/><text class="tick" x="984.4" y="269" text-anchor="middle">16</text><rect class="seg m1" x="1000.4" y="71.9" width="16.5" height="180.1" rx="3" data-tip="2026-07-17|Opus 4.8|153 turns of 159"/><rect class="seg m3" x="1000.4" y="64.8" width="16.5" height="5.1" rx="0" data-tip="2026-07-17|Fable 5|6 turns of 159"/><rect class="hit" x="996.5" y="16" width="24.2" height="238" data-tip="2026-07-17|Total|159 user turns"/><text class="tick" x="1008.6" y="269" text-anchor="middle">17</text><rect class="seg m1" x="1024.6" y="95.7" width="16.5" height="156.3" rx="3" data-tip="2026-07-18|Opus 4.8|133 turns of 138"/><rect class="seg m0" x="1024.6" y="89.8" width="16.5" height="4.0" rx="0" data-tip="2026-07-18|No reply|5 turns of 138"/><rect class="hit" x="1020.7" y="16" width="24.2" height="238" data-tip="2026-07-18|Total|138 user turns"/><text class="tick" x="1032.8" y="269" text-anchor="middle">18</text><rect class="seg m1" x="1048.8" y="91.0" width="16.5" height="161.0" rx="3" data-tip="2026-07-19|Opus 4.8|137 turns of 139"/><rect class="seg m0" x="1048.8" y="88.6" width="16.5" height="0.8" rx="0" data-tip="2026-07-19|No reply|2 turns of 139"/><rect class="hit" x="1044.9" y="16" width="24.2" height="238" data-tip="2026-07-19|Total|139 user turns"/><text class="tick" x="1057.0" y="269" text-anchor="middle">19</text><rect class="seg m1" x="1073.0" y="138.6" width="16.5" height="113.4" rx="3" data-tip="2026-07-20|Opus 4.8|97 turns of 99"/><rect class="seg m0" x="1073.0" y="136.2" width="16.5" height="0.8" rx="0" data-tip="2026-07-20|No reply|2 turns of 99"/><rect class="hit" x="1069.1" y="16" width="24.2" height="238" data-tip="2026-07-20|Total|99 user turns"/><text class="tick" x="1081.2" y="269" text-anchor="middle">20</text><rect class="seg m1" x="1097.2" y="144.5" width="16.5" height="107.5" rx="3" data-tip="2026-07-21|Opus 4.8|92 turns of 92"/><rect class="hit" x="1093.3" y="16" width="24.2" height="238" data-tip="2026-07-21|Total|92 user turns"/><text class="tick" x="1105.5" y="269" text-anchor="middle">21</text><rect class="seg m1" x="1121.4" y="242.1" width="16.5" height="9.9" rx="3" data-tip="2026-07-22|Opus 4.8|10 turns of 33"/><rect class="seg m5" x="1121.4" y="223.1" width="16.5" height="17.0" rx="0" data-tip="2026-07-22|Kimi K3|16 turns of 33"/><rect class="seg m6" x="1121.4" y="214.7" width="16.5" height="6.3" rx="0" data-tip="2026-07-22|Sonnet 5|7 turns of 33"/><rect class="hit" x="1117.6" y="16" width="24.2" height="238" data-tip="2026-07-22|Total|33 user turns"/><text class="tick" x="1129.7" y="269" text-anchor="middle">22</text><rect class="seg m1" x="1145.7" y="226.6" width="16.5" height="25.4" rx="3" data-tip="2026-07-23|Opus 4.8|23 turns of 93"/><rect class="seg m3" x="1145.7" y="143.3" width="16.5" height="81.3" rx="0" data-tip="2026-07-23|Fable 5|70 turns of 93"/><rect class="hit" x="1141.8" y="16" width="24.2" height="238" data-tip="2026-07-23|Total|93 user turns"/><text class="tick" x="1153.9" y="269" text-anchor="middle">23</text><text class="dlabel" x="112.5" y="48.3" text-anchor="middle">167</text><text class="dlabel" x="1008.6" y="57.8" text-anchor="middle">159</text></svg></div>
    <div class="legend"><span class="lg"><i class="sw m1"></i>Opus 4.8 <b>1418</b></span><span class="lg"><i class="sw m2"></i>Opus 4.7 <b>424</b></span><span class="lg"><i class="sw m3"></i>Fable 5 <b>275</b></span><span class="lg"><i class="sw m5"></i>Kimi K3 <b>16</b></span><span class="lg"><i class="sw m6"></i>Sonnet 5 <b>7</b></span><span class="lg"><i class="sw m0"></i>No reply <b>38</b></span></div>
  </div>
</div>

<div class="rpt wide">
<details class="tbl"><summary>Table view — turns per day by model</summary>
    <div class="scroll"><table class="dt num"><thead><tr><th scope="col">Day</th><th>Opus 4.8</th><th>Opus 4.7</th><th>Fable 5</th><th>Kimi K3</th><th>Sonnet 5</th><th>No reply</th><th scope="col">Turns</th><th scope="col">Est. cost</th></tr></thead><tbody><tr><th scope="row">2026-05-20</th><td></td><td>62</td><td></td><td></td><td></td><td></td><td class="tot">62</td><td class="tot">$225.98</td></tr><tr><th scope="row">2026-05-21</th><td></td><td>7</td><td></td><td></td><td></td><td>5</td><td class="tot">12</td><td class="tot">$2.18</td></tr><tr><th scope="row">2026-05-22</th><td></td><td>167</td><td></td><td></td><td></td><td></td><td class="tot">167</td><td class="tot">$330.36</td></tr><tr><th scope="row">2026-05-23</th><td></td><td>43</td><td></td><td></td><td></td><td></td><td class="tot">43</td><td class="tot">$204.83</td></tr><tr><th scope="row">2026-05-24</th><td></td><td>26</td><td></td><td></td><td></td><td></td><td class="tot">26</td><td class="tot">$66.77</td></tr><tr><th scope="row">2026-05-25</th><td></td><td>37</td><td></td><td></td><td></td><td></td><td class="tot">37</td><td class="tot">$224.60</td></tr><tr><th scope="row">2026-05-26</th><td></td><td>23</td><td></td><td></td><td></td><td></td><td class="tot">23</td><td class="tot">$404.88</td></tr><tr><th scope="row">2026-05-27</th><td></td><td>31</td><td></td><td></td><td></td><td>1</td><td class="tot">32</td><td class="tot">$298.21</td></tr><tr><th scope="row">2026-05-28</th><td>12</td><td>6</td><td></td><td></td><td></td><td></td><td class="tot">18</td><td class="tot">$266.97</td></tr><tr><th scope="row">2026-05-29</th><td>30</td><td></td><td></td><td></td><td></td><td></td><td class="tot">30</td><td class="tot">$573.48</td></tr><tr><th scope="row">2026-05-30</th><td>8</td><td>1</td><td></td><td></td><td></td><td></td><td class="tot">9</td><td class="tot">$53.71</td></tr><tr><th scope="row">2026-06-04</th><td>3</td><td>7</td><td></td><td></td><td></td><td></td><td class="tot">10</td><td class="tot">$4.96</td></tr><tr><th scope="row">2026-06-05</th><td></td><td>10</td><td></td><td></td><td></td><td></td><td class="tot">10</td><td class="tot">$4.70</td></tr><tr><th scope="row">2026-06-10</th><td></td><td></td><td>5</td><td></td><td></td><td>1</td><td class="tot">6</td><td class="tot">$85.90</td></tr><tr><th scope="row">2026-06-28</th><td>14</td><td></td><td></td><td></td><td></td><td></td><td class="tot">14</td><td class="tot">$272.97</td></tr><tr><th scope="row">2026-06-29</th><td>11</td><td></td><td></td><td></td><td></td><td></td><td class="tot">11</td><td class="tot">$351.75</td></tr><tr><th scope="row">2026-06-30</th><td>8</td><td></td><td></td><td></td><td></td><td></td><td class="tot">8</td><td class="tot">$192.34</td></tr><tr><th scope="row">2026-07-01</th><td>15</td><td></td><td>5</td><td></td><td></td><td>13</td><td class="tot">33</td><td class="tot">$486.88</td></tr><tr><th scope="row">2026-07-02</th><td>24</td><td></td><td>28</td><td></td><td></td><td></td><td class="tot">52</td><td class="tot">$553.05</td></tr><tr><th scope="row">2026-07-03</th><td>10</td><td></td><td>55</td><td></td><td></td><td></td><td class="tot">65</td><td class="tot">$448.39</td></tr><tr><th scope="row">2026-07-04</th><td>25</td><td></td><td>25</td><td></td><td></td><td></td><td class="tot">50</td><td class="tot">$876.18</td></tr><tr><th scope="row">2026-07-05</th><td>58</td><td></td><td></td><td></td><td></td><td>1</td><td class="tot">59</td><td class="tot">$471.15</td></tr><tr><th scope="row">2026-07-06</th><td>133</td><td></td><td>13</td><td></td><td></td><td></td><td class="tot">146</td><td class="tot">$599.92</td></tr><tr><th scope="row">2026-07-07</th><td>55</td><td></td><td>1</td><td></td><td></td><td></td><td class="tot">56</td><td class="tot">$407.79</td></tr><tr><th scope="row">2026-07-08</th><td>59</td><td>3</td><td></td><td></td><td></td><td></td><td class="tot">62</td><td class="tot">$107.37</td></tr><tr><th scope="row">2026-07-09</th><td>53</td><td>1</td><td>29</td><td></td><td></td><td>3</td><td class="tot">86</td><td class="tot">$664.24</td></tr><tr><th scope="row">2026-07-10</th><td>3</td><td></td><td>11</td><td></td><td></td><td></td><td class="tot">14</td><td class="tot">$597.21</td></tr><tr><th scope="row">2026-07-11</th><td>11</td><td></td><td>3</td><td></td><td></td><td></td><td class="tot">14</td><td class="tot">$524.09</td></tr><tr><th scope="row">2026-07-12</th><td>97</td><td></td><td></td><td></td><td></td><td>2</td><td class="tot">99</td><td class="tot">$483.60</td></tr><tr><th scope="row">2026-07-13</th><td>62</td><td></td><td></td><td></td><td></td><td></td><td class="tot">62</td><td class="tot">$421.32</td></tr><tr><th scope="row">2026-07-14</th><td>46</td><td></td><td></td><td></td><td></td><td>3</td><td class="tot">49</td><td class="tot">$377.41</td></tr><tr><th scope="row">2026-07-15</th><td>31</td><td></td><td>2</td><td></td><td></td><td></td><td class="tot">33</td><td class="tot">$261.41</td></tr><tr><th scope="row">2026-07-16</th><td>5</td><td></td><td>22</td><td></td><td></td><td></td><td class="tot">27</td><td class="tot">$676.39</td></tr><tr><th scope="row">2026-07-17</th><td>153</td><td></td><td>6</td><td></td><td></td><td></td><td class="tot">159</td><td class="tot">$438.89</td></tr><tr><th scope="row">2026-07-18</th><td>133</td><td></td><td></td><td></td><td></td><td>5</td><td class="tot">138</td><td class="tot">$524.43</td></tr><tr><th scope="row">2026-07-19</th><td>137</td><td></td><td></td><td></td><td></td><td>2</td><td class="tot">139</td><td class="tot">$513.46</td></tr><tr><th scope="row">2026-07-20</th><td>97</td><td></td><td></td><td></td><td></td><td>2</td><td class="tot">99</td><td class="tot">$542.57</td></tr><tr><th scope="row">2026-07-21</th><td>92</td><td></td><td></td><td></td><td></td><td></td><td class="tot">92</td><td class="tot">$568.66</td></tr><tr><th scope="row">2026-07-22</th><td>10</td><td></td><td></td><td>16</td><td>7</td><td></td><td class="tot">33</td><td class="tot">$113.46</td></tr><tr><th scope="row">2026-07-23</th><td>23</td><td></td><td>70</td><td></td><td></td><td></td><td class="tot">93</td><td class="tot">$537.50</td></tr></tbody><tfoot><tr><th scope="row">Total</th><td>1418</td><td>424</td><td>275</td><td>16</td><td>7</td><td>38</td><td class="tot">2178</td><td class="tot">$14,760</td></tr></tfoot></table></div>
  </details>
</div>

<p>Two things fall out of that chart. The bring-up is not a smooth ramp — it is four bursts separated by two multi-week gaps, and the busiest days are all in the last fortnight, after the driver already worked. And the 2,178 prompts are spread over just 40 active days, which is roughly 54 typed messages on a day when anything was happening at all.</p>

<h3>Daily token usage</h3>

<div class="rpt wide">
<div class="card">
    <div class="minis">
      <figure class="mini"><figcaption>Input<span>4.18M total</span></figcaption><svg class="chart" viewBox="0 0 560 150" role="img" aria-label="Daily Input"><line class="grid" x1="56" x2="550" y1="124.0" y2="124.0"/><text class="tick" x="48" y="127.5" text-anchor="end">0</text><line class="grid" x1="56" x2="550" y1="69.0" y2="69.0"/><text class="tick" x="48" y="72.5" text-anchor="end">500K</text><line class="grid" x1="56" x2="550" y1="14.0" y2="14.0"/><text class="tick" x="48" y="17.5" text-anchor="end">1M</text><line class="axis" x1="56" x2="550" y1="124" y2="124"/><rect class="seg m1" x="58.1" y="119.8" width="8.2" height="4.2" rx="2"/><rect class="hit" x="56.0" y="14" width="12.3" height="110" data-tip="2026-05-20|Input|38.3K tokens"/><rect class="seg m1" x="70.4" y="124.0" width="8.2" height="0.8" rx="2"/><rect class="hit" x="68.3" y="14" width="12.3" height="110" data-tip="2026-05-21|Input|60 tokens"/><rect class="seg m1" x="82.8" y="123.7" width="8.2" height="0.8" rx="2"/><rect class="hit" x="80.7" y="14" width="12.3" height="110" data-tip="2026-05-22|Input|2.49K tokens"/><rect class="seg m1" x="95.1" y="123.3" width="8.2" height="0.8" rx="2"/><rect class="hit" x="93.0" y="14" width="12.3" height="110" data-tip="2026-05-23|Input|6.17K tokens"/><rect class="seg m1" x="107.5" y="116.4" width="8.2" height="7.6" rx="2"/><rect class="hit" x="105.4" y="14" width="12.3" height="110" data-tip="2026-05-24|Input|69.1K tokens"/><rect class="seg m1" x="119.8" y="120.0" width="8.2" height="4.0" rx="2"/><rect class="hit" x="117.8" y="14" width="12.3" height="110" data-tip="2026-05-25|Input|36.4K tokens"/><rect class="seg m1" x="132.2" y="110.8" width="8.2" height="13.2" rx="2"/><rect class="hit" x="130.1" y="14" width="12.3" height="110" data-tip="2026-05-26|Input|120.4K tokens"/><rect class="seg m1" x="144.5" y="119.3" width="8.2" height="4.7" rx="2"/><rect class="hit" x="142.4" y="14" width="12.3" height="110" data-tip="2026-05-27|Input|42.7K tokens"/><rect class="seg m1" x="156.9" y="113.7" width="8.2" height="10.3" rx="2"/><rect class="hit" x="154.8" y="14" width="12.3" height="110" data-tip="2026-05-28|Input|94K tokens"/><rect class="seg m1" x="169.2" y="97.8" width="8.2" height="26.2" rx="2"/><rect class="hit" x="167.1" y="14" width="12.3" height="110" data-tip="2026-05-29|Input|237.9K tokens"/><rect class="seg m1" x="181.6" y="122.2" width="8.2" height="1.8" rx="2"/><rect class="hit" x="179.5" y="14" width="12.3" height="110" data-tip="2026-05-30|Input|16K tokens"/><rect class="seg m1" x="193.9" y="123.5" width="8.2" height="0.8" rx="2"/><rect class="hit" x="191.8" y="14" width="12.3" height="110" data-tip="2026-06-04|Input|4.59K tokens"/><rect class="seg m1" x="206.3" y="123.6" width="8.2" height="0.8" rx="2"/><rect class="hit" x="204.2" y="14" width="12.3" height="110" data-tip="2026-06-05|Input|3.54K tokens"/><rect class="seg m1" x="218.6" y="120.1" width="8.2" height="3.9" rx="2"/><rect class="hit" x="216.5" y="14" width="12.3" height="110" data-tip="2026-06-10|Input|35.1K tokens"/><rect class="seg m1" x="231.0" y="110.9" width="8.2" height="13.1" rx="2"/><rect class="hit" x="228.9" y="14" width="12.3" height="110" data-tip="2026-06-28|Input|119.5K tokens"/><rect class="seg m1" x="243.3" y="106.4" width="8.2" height="17.6" rx="2"/><rect class="hit" x="241.2" y="14" width="12.3" height="110" data-tip="2026-06-29|Input|160.4K tokens"/><rect class="seg m1" x="255.7" y="115.9" width="8.2" height="8.1" rx="2"/><rect class="hit" x="253.6" y="14" width="12.3" height="110" data-tip="2026-06-30|Input|74K tokens"/><rect class="seg m1" x="268.0" y="102.1" width="8.2" height="21.9" rx="2"/><rect class="hit" x="265.9" y="14" width="12.3" height="110" data-tip="2026-07-01|Input|198.8K tokens"/><rect class="seg m1" x="280.4" y="96.0" width="8.2" height="28.0" rx="2"/><rect class="hit" x="278.3" y="14" width="12.3" height="110" data-tip="2026-07-02|Input|254.6K tokens"/><rect class="seg m1" x="292.7" y="102.6" width="8.2" height="21.4" rx="2"/><rect class="hit" x="290.6" y="14" width="12.3" height="110" data-tip="2026-07-03|Input|194.8K tokens"/><rect class="seg m1" x="305.1" y="105.7" width="8.2" height="18.3" rx="2"/><rect class="hit" x="303.0" y="14" width="12.3" height="110" data-tip="2026-07-04|Input|166.4K tokens"/><rect class="seg m1" x="317.4" y="102.4" width="8.2" height="21.6" rx="2"/><rect class="hit" x="315.3" y="14" width="12.3" height="110" data-tip="2026-07-05|Input|196.4K tokens"/><rect class="seg m1" x="329.8" y="82.1" width="8.2" height="41.9" rx="2"/><rect class="hit" x="327.7" y="14" width="12.3" height="110" data-tip="2026-07-06|Input|380.6K tokens"/><rect class="seg m1" x="342.1" y="101.8" width="8.2" height="22.2" rx="2"/><rect class="hit" x="340.1" y="14" width="12.3" height="110" data-tip="2026-07-07|Input|201.5K tokens"/><rect class="seg m1" x="354.5" y="107.4" width="8.2" height="16.6" rx="2"/><rect class="hit" x="352.4" y="14" width="12.3" height="110" data-tip="2026-07-08|Input|150.8K tokens"/><rect class="seg m1" x="366.8" y="99.7" width="8.2" height="24.3" rx="2"/><rect class="hit" x="364.8" y="14" width="12.3" height="110" data-tip="2026-07-09|Input|221.4K tokens"/><rect class="seg m1" x="379.2" y="105.3" width="8.2" height="18.7" rx="2"/><rect class="hit" x="377.1" y="14" width="12.3" height="110" data-tip="2026-07-10|Input|169.7K tokens"/><rect class="seg m1" x="391.5" y="119.1" width="8.2" height="4.9" rx="2"/><rect class="hit" x="389.4" y="14" width="12.3" height="110" data-tip="2026-07-11|Input|44.3K tokens"/><rect class="seg m1" x="403.9" y="123.6" width="8.2" height="0.8" rx="2"/><rect class="hit" x="401.8" y="14" width="12.3" height="110" data-tip="2026-07-12|Input|3.4K tokens"/><rect class="seg m1" x="416.2" y="123.4" width="8.2" height="0.8" rx="2"/><rect class="hit" x="414.1" y="14" width="12.3" height="110" data-tip="2026-07-13|Input|5.71K tokens"/><rect class="seg m1" x="428.6" y="123.8" width="8.2" height="0.8" rx="2"/><rect class="hit" x="426.5" y="14" width="12.3" height="110" data-tip="2026-07-14|Input|2.18K tokens"/><rect class="seg m1" x="440.9" y="123.8" width="8.2" height="0.8" rx="2"/><rect class="hit" x="438.8" y="14" width="12.3" height="110" data-tip="2026-07-15|Input|1.54K tokens"/><rect class="seg m1" x="453.3" y="122.7" width="8.2" height="1.3" rx="2"/><rect class="hit" x="451.2" y="14" width="12.3" height="110" data-tip="2026-07-16|Input|11.6K tokens"/><rect class="seg m1" x="465.6" y="123.4" width="8.2" height="0.8" rx="2"/><rect class="hit" x="463.6" y="14" width="12.3" height="110" data-tip="2026-07-17|Input|5.83K tokens"/><rect class="seg m1" x="478.0" y="119.9" width="8.2" height="4.1" rx="2"/><rect class="hit" x="475.9" y="14" width="12.3" height="110" data-tip="2026-07-18|Input|37K tokens"/><rect class="seg m1" x="490.3" y="122.8" width="8.2" height="1.2" rx="2"/><rect class="hit" x="488.2" y="14" width="12.3" height="110" data-tip="2026-07-19|Input|10.6K tokens"/><rect class="seg m1" x="502.7" y="116.8" width="8.2" height="7.2" rx="2"/><rect class="hit" x="500.6" y="14" width="12.3" height="110" data-tip="2026-07-20|Input|65.7K tokens"/><rect class="seg m1" x="515.0" y="120.4" width="8.2" height="3.6" rx="2"/><rect class="hit" x="513.0" y="14" width="12.3" height="110" data-tip="2026-07-21|Input|33K tokens"/><rect class="seg m1" x="527.4" y="39.9" width="8.2" height="84.1" rx="2"/><rect class="hit" x="525.3" y="14" width="12.3" height="110" data-tip="2026-07-22|Input|764.1K tokens"/><rect class="seg m1" x="539.7" y="123.6" width="8.2" height="0.8" rx="2"/><rect class="hit" x="537.6" y="14" width="12.3" height="110" data-tip="2026-07-23|Input|3.28K tokens"/><text class="tick" x="58.1" y="140" text-anchor="start">May 20</text><text class="tick" x="547.9" y="140" text-anchor="end">Jul 23</text></svg></figure>
      <figure class="mini"><figcaption>Output<span>67.4M total</span></figcaption><svg class="chart" viewBox="0 0 560 150" role="img" aria-label="Daily Output"><line class="grid" x1="56" x2="550" y1="124.0" y2="124.0"/><text class="tick" x="48" y="127.5" text-anchor="end">0</text><line class="grid" x1="56" x2="550" y1="69.0" y2="69.0"/><text class="tick" x="48" y="72.5" text-anchor="end">2M</text><line class="grid" x1="56" x2="550" y1="14.0" y2="14.0"/><text class="tick" x="48" y="17.5" text-anchor="end">4M</text><line class="axis" x1="56" x2="550" y1="124" y2="124"/><rect class="seg m1" x="58.1" y="85.3" width="8.2" height="38.7" rx="2"/><rect class="hit" x="56.0" y="14" width="12.3" height="110" data-tip="2026-05-20|Output|1.41M tokens"/><rect class="seg m1" x="70.4" y="123.5" width="8.2" height="0.8" rx="2"/><rect class="hit" x="68.3" y="14" width="12.3" height="110" data-tip="2026-05-21|Output|19.6K tokens"/><rect class="seg m1" x="82.8" y="98.3" width="8.2" height="25.7" rx="2"/><rect class="hit" x="80.7" y="14" width="12.3" height="110" data-tip="2026-05-22|Output|933.4K tokens"/><rect class="seg m1" x="95.1" y="101.6" width="8.2" height="22.4" rx="2"/><rect class="hit" x="93.0" y="14" width="12.3" height="110" data-tip="2026-05-23|Output|813.5K tokens"/><rect class="seg m1" x="107.5" y="106.5" width="8.2" height="17.5" rx="2"/><rect class="hit" x="105.4" y="14" width="12.3" height="110" data-tip="2026-05-24|Output|634.7K tokens"/><rect class="seg m1" x="119.8" y="86.3" width="8.2" height="37.7" rx="2"/><rect class="hit" x="117.8" y="14" width="12.3" height="110" data-tip="2026-05-25|Output|1.37M tokens"/><rect class="seg m1" x="132.2" y="48.3" width="8.2" height="75.7" rx="2"/><rect class="hit" x="130.1" y="14" width="12.3" height="110" data-tip="2026-05-26|Output|2.75M tokens"/><rect class="seg m1" x="144.5" y="51.9" width="8.2" height="72.1" rx="2"/><rect class="hit" x="142.4" y="14" width="12.3" height="110" data-tip="2026-05-27|Output|2.62M tokens"/><rect class="seg m1" x="156.9" y="77.4" width="8.2" height="46.6" rx="2"/><rect class="hit" x="154.8" y="14" width="12.3" height="110" data-tip="2026-05-28|Output|1.7M tokens"/><rect class="seg m1" x="169.2" y="21.6" width="8.2" height="102.4" rx="2"/><rect class="hit" x="167.1" y="14" width="12.3" height="110" data-tip="2026-05-29|Output|3.72M tokens"/><rect class="seg m1" x="181.6" y="115.4" width="8.2" height="8.6" rx="2"/><rect class="hit" x="179.5" y="14" width="12.3" height="110" data-tip="2026-05-30|Output|312.8K tokens"/><rect class="seg m1" x="193.9" y="122.0" width="8.2" height="2.0" rx="2"/><rect class="hit" x="191.8" y="14" width="12.3" height="110" data-tip="2026-06-04|Output|72.8K tokens"/><rect class="seg m1" x="206.3" y="122.3" width="8.2" height="1.7" rx="2"/><rect class="hit" x="204.2" y="14" width="12.3" height="110" data-tip="2026-06-05|Output|61.6K tokens"/><rect class="seg m1" x="218.6" y="114.3" width="8.2" height="9.7" rx="2"/><rect class="hit" x="216.5" y="14" width="12.3" height="110" data-tip="2026-06-10|Output|352.9K tokens"/><rect class="seg m1" x="231.0" y="65.0" width="8.2" height="59.0" rx="2"/><rect class="hit" x="228.9" y="14" width="12.3" height="110" data-tip="2026-06-28|Output|2.15M tokens"/><rect class="seg m1" x="243.3" y="53.2" width="8.2" height="70.8" rx="2"/><rect class="hit" x="241.2" y="14" width="12.3" height="110" data-tip="2026-06-29|Output|2.58M tokens"/><rect class="seg m1" x="255.7" y="82.7" width="8.2" height="41.3" rx="2"/><rect class="hit" x="253.6" y="14" width="12.3" height="110" data-tip="2026-06-30|Output|1.5M tokens"/><rect class="seg m1" x="268.0" y="94.0" width="8.2" height="30.0" rx="2"/><rect class="hit" x="265.9" y="14" width="12.3" height="110" data-tip="2026-07-01|Output|1.09M tokens"/><rect class="seg m1" x="280.4" y="73.1" width="8.2" height="50.9" rx="2"/><rect class="hit" x="278.3" y="14" width="12.3" height="110" data-tip="2026-07-02|Output|1.85M tokens"/><rect class="seg m1" x="292.7" y="79.0" width="8.2" height="45.0" rx="2"/><rect class="hit" x="290.6" y="14" width="12.3" height="110" data-tip="2026-07-03|Output|1.63M tokens"/><rect class="seg m1" x="305.1" y="78.4" width="8.2" height="45.6" rx="2"/><rect class="hit" x="303.0" y="14" width="12.3" height="110" data-tip="2026-07-04|Output|1.66M tokens"/><rect class="seg m1" x="317.4" y="32.0" width="8.2" height="92.0" rx="2"/><rect class="hit" x="315.3" y="14" width="12.3" height="110" data-tip="2026-07-05|Output|3.35M tokens"/><rect class="seg m1" x="329.8" y="26.3" width="8.2" height="97.7" rx="2"/><rect class="hit" x="327.7" y="14" width="12.3" height="110" data-tip="2026-07-06|Output|3.55M tokens"/><rect class="seg m1" x="342.1" y="69.3" width="8.2" height="54.7" rx="2"/><rect class="hit" x="340.1" y="14" width="12.3" height="110" data-tip="2026-07-07|Output|1.99M tokens"/><rect class="seg m1" x="354.5" y="103.6" width="8.2" height="20.4" rx="2"/><rect class="hit" x="352.4" y="14" width="12.3" height="110" data-tip="2026-07-08|Output|740.1K tokens"/><rect class="seg m1" x="366.8" y="71.1" width="8.2" height="52.9" rx="2"/><rect class="hit" x="364.8" y="14" width="12.3" height="110" data-tip="2026-07-09|Output|1.93M tokens"/><rect class="seg m1" x="379.2" y="95.6" width="8.2" height="28.4" rx="2"/><rect class="hit" x="377.1" y="14" width="12.3" height="110" data-tip="2026-07-10|Output|1.03M tokens"/><rect class="seg m1" x="391.5" y="91.9" width="8.2" height="32.1" rx="2"/><rect class="hit" x="389.4" y="14" width="12.3" height="110" data-tip="2026-07-11|Output|1.17M tokens"/><rect class="seg m1" x="403.9" y="60.0" width="8.2" height="64.0" rx="2"/><rect class="hit" x="401.8" y="14" width="12.3" height="110" data-tip="2026-07-12|Output|2.33M tokens"/><rect class="seg m1" x="416.2" y="46.3" width="8.2" height="77.7" rx="2"/><rect class="hit" x="414.1" y="14" width="12.3" height="110" data-tip="2026-07-13|Output|2.83M tokens"/><rect class="seg m1" x="428.6" y="42.2" width="8.2" height="81.8" rx="2"/><rect class="hit" x="426.5" y="14" width="12.3" height="110" data-tip="2026-07-14|Output|2.97M tokens"/><rect class="seg m1" x="440.9" y="80.6" width="8.2" height="43.4" rx="2"/><rect class="hit" x="438.8" y="14" width="12.3" height="110" data-tip="2026-07-15|Output|1.58M tokens"/><rect class="seg m1" x="453.3" y="74.4" width="8.2" height="49.6" rx="2"/><rect class="hit" x="451.2" y="14" width="12.3" height="110" data-tip="2026-07-16|Output|1.8M tokens"/><rect class="seg m1" x="465.6" y="53.2" width="8.2" height="70.8" rx="2"/><rect class="hit" x="463.6" y="14" width="12.3" height="110" data-tip="2026-07-17|Output|2.57M tokens"/><rect class="seg m1" x="478.0" y="63.8" width="8.2" height="60.2" rx="2"/><rect class="hit" x="475.9" y="14" width="12.3" height="110" data-tip="2026-07-18|Output|2.19M tokens"/><rect class="seg m1" x="490.3" y="75.0" width="8.2" height="49.0" rx="2"/><rect class="hit" x="488.2" y="14" width="12.3" height="110" data-tip="2026-07-19|Output|1.78M tokens"/><rect class="seg m1" x="502.7" y="56.6" width="8.2" height="67.4" rx="2"/><rect class="hit" x="500.6" y="14" width="12.3" height="110" data-tip="2026-07-20|Output|2.45M tokens"/><rect class="seg m1" x="515.0" y="69.8" width="8.2" height="54.2" rx="2"/><rect class="hit" x="513.0" y="14" width="12.3" height="110" data-tip="2026-07-21|Output|1.97M tokens"/><rect class="seg m1" x="527.4" y="102.0" width="8.2" height="22.0" rx="2"/><rect class="hit" x="525.3" y="14" width="12.3" height="110" data-tip="2026-07-22|Output|801.8K tokens"/><rect class="seg m1" x="539.7" y="91.8" width="8.2" height="32.2" rx="2"/><rect class="hit" x="537.6" y="14" width="12.3" height="110" data-tip="2026-07-23|Output|1.17M tokens"/><text class="tick" x="58.1" y="140" text-anchor="start">May 20</text><text class="tick" x="547.9" y="140" text-anchor="end">Jul 23</text></svg></figure>
      <figure class="mini"><figcaption>Cache write<span>233.9M total</span></figcaption><svg class="chart" viewBox="0 0 560 150" role="img" aria-label="Daily Cache write"><line class="grid" x1="56" x2="550" y1="124.0" y2="124.0"/><text class="tick" x="48" y="127.5" text-anchor="end">0</text><line class="grid" x1="56" x2="550" y1="69.0" y2="69.0"/><text class="tick" x="48" y="72.5" text-anchor="end">10M</text><line class="grid" x1="56" x2="550" y1="14.0" y2="14.0"/><text class="tick" x="48" y="17.5" text-anchor="end">20M</text><line class="axis" x1="56" x2="550" y1="124" y2="124"/><rect class="seg m1" x="58.1" y="95.9" width="8.2" height="28.1" rx="2"/><rect class="hit" x="56.0" y="14" width="12.3" height="110" data-tip="2026-05-20|Cache write|5.1M tokens"/><rect class="seg m1" x="70.4" y="123.4" width="8.2" height="0.8" rx="2"/><rect class="hit" x="68.3" y="14" width="12.3" height="110" data-tip="2026-05-21|Cache write|115.5K tokens"/><rect class="seg m1" x="82.8" y="87.7" width="8.2" height="36.3" rx="2"/><rect class="hit" x="80.7" y="14" width="12.3" height="110" data-tip="2026-05-22|Cache write|6.6M tokens"/><rect class="seg m1" x="95.1" y="94.3" width="8.2" height="29.7" rx="2"/><rect class="hit" x="93.0" y="14" width="12.3" height="110" data-tip="2026-05-23|Cache write|5.39M tokens"/><rect class="seg m1" x="107.5" y="107.1" width="8.2" height="16.9" rx="2"/><rect class="hit" x="105.4" y="14" width="12.3" height="110" data-tip="2026-05-24|Cache write|3.06M tokens"/><rect class="seg m1" x="119.8" y="90.5" width="8.2" height="33.5" rx="2"/><rect class="hit" x="117.8" y="14" width="12.3" height="110" data-tip="2026-05-25|Cache write|6.09M tokens"/><rect class="seg m1" x="132.2" y="80.6" width="8.2" height="43.4" rx="2"/><rect class="hit" x="130.1" y="14" width="12.3" height="110" data-tip="2026-05-26|Cache write|7.88M tokens"/><rect class="seg m1" x="144.5" y="92.6" width="8.2" height="31.4" rx="2"/><rect class="hit" x="142.4" y="14" width="12.3" height="110" data-tip="2026-05-27|Cache write|5.71M tokens"/><rect class="seg m1" x="156.9" y="92.6" width="8.2" height="31.4" rx="2"/><rect class="hit" x="154.8" y="14" width="12.3" height="110" data-tip="2026-05-28|Cache write|5.7M tokens"/><rect class="seg m1" x="169.2" y="75.7" width="8.2" height="48.3" rx="2"/><rect class="hit" x="167.1" y="14" width="12.3" height="110" data-tip="2026-05-29|Cache write|8.77M tokens"/><rect class="seg m1" x="181.6" y="121.6" width="8.2" height="2.4" rx="2"/><rect class="hit" x="179.5" y="14" width="12.3" height="110" data-tip="2026-05-30|Cache write|428.9K tokens"/><rect class="seg m1" x="193.9" y="121.3" width="8.2" height="2.7" rx="2"/><rect class="hit" x="191.8" y="14" width="12.3" height="110" data-tip="2026-06-04|Cache write|490.5K tokens"/><rect class="seg m1" x="206.3" y="122.7" width="8.2" height="1.3" rx="2"/><rect class="hit" x="204.2" y="14" width="12.3" height="110" data-tip="2026-06-05|Cache write|240.3K tokens"/><rect class="seg m1" x="218.6" y="116.6" width="8.2" height="7.4" rx="2"/><rect class="hit" x="216.5" y="14" width="12.3" height="110" data-tip="2026-06-10|Cache write|1.35M tokens"/><rect class="seg m1" x="231.0" y="97.8" width="8.2" height="26.2" rx="2"/><rect class="hit" x="228.9" y="14" width="12.3" height="110" data-tip="2026-06-28|Cache write|4.76M tokens"/><rect class="seg m1" x="243.3" y="92.3" width="8.2" height="31.7" rx="2"/><rect class="hit" x="241.2" y="14" width="12.3" height="110" data-tip="2026-06-29|Cache write|5.77M tokens"/><rect class="seg m1" x="255.7" y="102.5" width="8.2" height="21.5" rx="2"/><rect class="hit" x="253.6" y="14" width="12.3" height="110" data-tip="2026-06-30|Cache write|3.92M tokens"/><rect class="seg m1" x="268.0" y="100.6" width="8.2" height="23.4" rx="2"/><rect class="hit" x="265.9" y="14" width="12.3" height="110" data-tip="2026-07-01|Cache write|4.25M tokens"/><rect class="seg m1" x="280.4" y="79.1" width="8.2" height="44.9" rx="2"/><rect class="hit" x="278.3" y="14" width="12.3" height="110" data-tip="2026-07-02|Cache write|8.15M tokens"/><rect class="seg m1" x="292.7" y="92.1" width="8.2" height="31.9" rx="2"/><rect class="hit" x="290.6" y="14" width="12.3" height="110" data-tip="2026-07-03|Cache write|5.8M tokens"/><rect class="seg m1" x="305.1" y="95.6" width="8.2" height="28.4" rx="2"/><rect class="hit" x="303.0" y="14" width="12.3" height="110" data-tip="2026-07-04|Cache write|5.17M tokens"/><rect class="seg m1" x="317.4" y="89.5" width="8.2" height="34.5" rx="2"/><rect class="hit" x="315.3" y="14" width="12.3" height="110" data-tip="2026-07-05|Cache write|6.27M tokens"/><rect class="seg m1" x="329.8" y="66.9" width="8.2" height="57.1" rx="2"/><rect class="hit" x="327.7" y="14" width="12.3" height="110" data-tip="2026-07-06|Cache write|10.4M tokens"/><rect class="seg m1" x="342.1" y="95.0" width="8.2" height="29.0" rx="2"/><rect class="hit" x="340.1" y="14" width="12.3" height="110" data-tip="2026-07-07|Cache write|5.26M tokens"/><rect class="seg m1" x="354.5" y="107.5" width="8.2" height="16.5" rx="2"/><rect class="hit" x="352.4" y="14" width="12.3" height="110" data-tip="2026-07-08|Cache write|3.01M tokens"/><rect class="seg m1" x="366.8" y="86.1" width="8.2" height="37.9" rx="2"/><rect class="hit" x="364.8" y="14" width="12.3" height="110" data-tip="2026-07-09|Cache write|6.89M tokens"/><rect class="seg m1" x="379.2" y="109.2" width="8.2" height="14.8" rx="2"/><rect class="hit" x="377.1" y="14" width="12.3" height="110" data-tip="2026-07-10|Cache write|2.69M tokens"/><rect class="seg m1" x="391.5" y="106.9" width="8.2" height="17.1" rx="2"/><rect class="hit" x="389.4" y="14" width="12.3" height="110" data-tip="2026-07-11|Cache write|3.11M tokens"/><rect class="seg m1" x="403.9" y="71.8" width="8.2" height="52.2" rx="2"/><rect class="hit" x="401.8" y="14" width="12.3" height="110" data-tip="2026-07-12|Cache write|9.49M tokens"/><rect class="seg m1" x="416.2" y="79.8" width="8.2" height="44.2" rx="2"/><rect class="hit" x="414.1" y="14" width="12.3" height="110" data-tip="2026-07-13|Cache write|8.04M tokens"/><rect class="seg m1" x="428.6" y="80.6" width="8.2" height="43.4" rx="2"/><rect class="hit" x="426.5" y="14" width="12.3" height="110" data-tip="2026-07-14|Cache write|7.88M tokens"/><rect class="seg m1" x="440.9" y="96.1" width="8.2" height="27.9" rx="2"/><rect class="hit" x="438.8" y="14" width="12.3" height="110" data-tip="2026-07-15|Cache write|5.06M tokens"/><rect class="seg m1" x="453.3" y="86.4" width="8.2" height="37.6" rx="2"/><rect class="hit" x="451.2" y="14" width="12.3" height="110" data-tip="2026-07-16|Cache write|6.83M tokens"/><rect class="seg m1" x="465.6" y="60.1" width="8.2" height="63.9" rx="2"/><rect class="hit" x="463.6" y="14" width="12.3" height="110" data-tip="2026-07-17|Cache write|11.6M tokens"/><rect class="seg m1" x="478.0" y="62.2" width="8.2" height="61.8" rx="2"/><rect class="hit" x="475.9" y="14" width="12.3" height="110" data-tip="2026-07-18|Cache write|11.2M tokens"/><rect class="seg m1" x="490.3" y="66.0" width="8.2" height="58.0" rx="2"/><rect class="hit" x="488.2" y="14" width="12.3" height="110" data-tip="2026-07-19|Cache write|10.5M tokens"/><rect class="seg m1" x="502.7" y="49.7" width="8.2" height="74.3" rx="2"/><rect class="hit" x="500.6" y="14" width="12.3" height="110" data-tip="2026-07-20|Cache write|13.5M tokens"/><rect class="seg m1" x="515.0" y="79.9" width="8.2" height="44.1" rx="2"/><rect class="hit" x="513.0" y="14" width="12.3" height="110" data-tip="2026-07-21|Cache write|8.01M tokens"/><rect class="seg m1" x="527.4" y="109.7" width="8.2" height="14.3" rx="2"/><rect class="hit" x="525.3" y="14" width="12.3" height="110" data-tip="2026-07-22|Cache write|2.6M tokens"/><rect class="seg m1" x="539.7" y="87.3" width="8.2" height="36.7" rx="2"/><rect class="hit" x="537.6" y="14" width="12.3" height="110" data-tip="2026-07-23|Cache write|6.67M tokens"/><text class="tick" x="58.1" y="140" text-anchor="start">May 20</text><text class="tick" x="547.9" y="140" text-anchor="end">Jul 23</text></svg></figure>
      <figure class="mini"><figcaption>Cache read<span>18.3B total</span></figcaption><svg class="chart" viewBox="0 0 560 150" role="img" aria-label="Daily Cache read"><line class="grid" x1="56" x2="550" y1="124.0" y2="124.0"/><text class="tick" x="48" y="127.5" text-anchor="end">0</text><line class="grid" x1="56" x2="550" y1="69.0" y2="69.0"/><text class="tick" x="48" y="72.5" text-anchor="end">500M</text><line class="grid" x1="56" x2="550" y1="14.0" y2="14.0"/><text class="tick" x="48" y="17.5" text-anchor="end">1B</text><line class="axis" x1="56" x2="550" y1="124" y2="124"/><rect class="seg m1" x="58.1" y="85.7" width="8.2" height="38.3" rx="2"/><rect class="hit" x="56.0" y="14" width="12.3" height="110" data-tip="2026-05-20|Cache read|348.3M tokens"/><rect class="seg m1" x="70.4" y="123.8" width="8.2" height="0.8" rx="2"/><rect class="hit" x="68.3" y="14" width="12.3" height="110" data-tip="2026-05-21|Cache read|1.94M tokens"/><rect class="seg m1" x="82.8" y="64.7" width="8.2" height="59.3" rx="2"/><rect class="hit" x="80.7" y="14" width="12.3" height="110" data-tip="2026-05-22|Cache read|539M tokens"/><rect class="seg m1" x="95.1" y="90.2" width="8.2" height="33.8" rx="2"/><rect class="hit" x="93.0" y="14" width="12.3" height="110" data-tip="2026-05-23|Cache read|307.2M tokens"/><rect class="seg m1" x="107.5" y="117.1" width="8.2" height="6.9" rx="2"/><rect class="hit" x="105.4" y="14" width="12.3" height="110" data-tip="2026-05-24|Cache read|62.8M tokens"/><rect class="seg m1" x="119.8" y="89.9" width="8.2" height="34.1" rx="2"/><rect class="hit" x="117.8" y="14" width="12.3" height="110" data-tip="2026-05-25|Cache read|309.9M tokens"/><rect class="seg m1" x="132.2" y="61.0" width="8.2" height="63.0" rx="2"/><rect class="hit" x="130.1" y="14" width="12.3" height="110" data-tip="2026-05-26|Cache read|572.3M tokens"/><rect class="seg m1" x="144.5" y="80.4" width="8.2" height="43.6" rx="2"/><rect class="hit" x="142.4" y="14" width="12.3" height="110" data-tip="2026-05-27|Cache read|396.8M tokens"/><rect class="seg m1" x="156.9" y="81.0" width="8.2" height="43.0" rx="2"/><rect class="hit" x="154.8" y="14" width="12.3" height="110" data-tip="2026-05-28|Cache read|390.9M tokens"/><rect class="seg m1" x="169.2" y="30.6" width="8.2" height="93.4" rx="2"/><rect class="hit" x="167.1" y="14" width="12.3" height="110" data-tip="2026-05-29|Cache read|848.8M tokens"/><rect class="seg m1" x="181.6" y="114.5" width="8.2" height="9.5" rx="2"/><rect class="hit" x="179.5" y="14" width="12.3" height="110" data-tip="2026-05-30|Cache read|86.3M tokens"/><rect class="seg m1" x="193.9" y="123.3" width="8.2" height="0.8" rx="2"/><rect class="hit" x="191.8" y="14" width="12.3" height="110" data-tip="2026-06-04|Cache read|5.94M tokens"/><rect class="seg m1" x="206.3" y="123.6" width="8.2" height="0.8" rx="2"/><rect class="hit" x="204.2" y="14" width="12.3" height="110" data-tip="2026-06-05|Cache read|3.27M tokens"/><rect class="seg m1" x="218.6" y="117.8" width="8.2" height="6.2" rx="2"/><rect class="hit" x="216.5" y="14" width="12.3" height="110" data-tip="2026-06-10|Cache read|56.8M tokens"/><rect class="seg m1" x="231.0" y="82.4" width="8.2" height="41.6" rx="2"/><rect class="hit" x="228.9" y="14" width="12.3" height="110" data-tip="2026-06-28|Cache read|377.9M tokens"/><rect class="seg m1" x="243.3" y="67.4" width="8.2" height="56.6" rx="2"/><rect class="hit" x="241.2" y="14" width="12.3" height="110" data-tip="2026-06-29|Cache read|514.2M tokens"/><rect class="seg m1" x="255.7" y="95.4" width="8.2" height="28.6" rx="2"/><rect class="hit" x="253.6" y="14" width="12.3" height="110" data-tip="2026-06-30|Cache read|259.9M tokens"/><rect class="seg m1" x="268.0" y="76.2" width="8.2" height="47.8" rx="2"/><rect class="hit" x="265.9" y="14" width="12.3" height="110" data-tip="2026-07-01|Cache read|434.6M tokens"/><rect class="seg m1" x="280.4" y="69.8" width="8.2" height="54.2" rx="2"/><rect class="hit" x="278.3" y="14" width="12.3" height="110" data-tip="2026-07-02|Cache read|492.7M tokens"/><rect class="seg m1" x="292.7" y="84.2" width="8.2" height="39.8" rx="2"/><rect class="hit" x="290.6" y="14" width="12.3" height="110" data-tip="2026-07-03|Cache read|361.9M tokens"/><rect class="seg m1" x="305.1" y="36.8" width="8.2" height="87.2" rx="2"/><rect class="hit" x="303.0" y="14" width="12.3" height="110" data-tip="2026-07-04|Cache read|792.5M tokens"/><rect class="seg m1" x="317.4" y="47.6" width="8.2" height="76.4" rx="2"/><rect class="hit" x="315.3" y="14" width="12.3" height="110" data-tip="2026-07-05|Cache read|694.7M tokens"/><rect class="seg m1" x="329.8" y="36.5" width="8.2" height="87.5" rx="2"/><rect class="hit" x="327.7" y="14" width="12.3" height="110" data-tip="2026-07-06|Cache read|795.7M tokens"/><rect class="seg m1" x="342.1" y="61.0" width="8.2" height="63.0" rx="2"/><rect class="hit" x="340.1" y="14" width="12.3" height="110" data-tip="2026-07-07|Cache read|572.5M tokens"/><rect class="seg m1" x="354.5" y="108.7" width="8.2" height="15.3" rx="2"/><rect class="hit" x="352.4" y="14" width="12.3" height="110" data-tip="2026-07-08|Cache read|138.6M tokens"/><rect class="seg m1" x="366.8" y="52.3" width="8.2" height="71.7" rx="2"/><rect class="hit" x="364.8" y="14" width="12.3" height="110" data-tip="2026-07-09|Cache read|651.9M tokens"/><rect class="seg m1" x="379.2" y="67.8" width="8.2" height="56.2" rx="2"/><rect class="hit" x="377.1" y="14" width="12.3" height="110" data-tip="2026-07-10|Cache read|511.1M tokens"/><rect class="seg m1" x="391.5" y="67.9" width="8.2" height="56.1" rx="2"/><rect class="hit" x="389.4" y="14" width="12.3" height="110" data-tip="2026-07-11|Cache read|509.9M tokens"/><rect class="seg m1" x="403.9" y="43.5" width="8.2" height="80.5" rx="2"/><rect class="hit" x="401.8" y="14" width="12.3" height="110" data-tip="2026-07-12|Cache read|732.2M tokens"/><rect class="seg m1" x="416.2" y="57.9" width="8.2" height="66.1" rx="2"/><rect class="hit" x="414.1" y="14" width="12.3" height="110" data-tip="2026-07-13|Cache read|600.8M tokens"/><rect class="seg m1" x="428.6" y="68.2" width="8.2" height="55.8" rx="2"/><rect class="hit" x="426.5" y="14" width="12.3" height="110" data-tip="2026-07-14|Cache read|507.6M tokens"/><rect class="seg m1" x="440.9" y="82.2" width="8.2" height="41.8" rx="2"/><rect class="hit" x="438.8" y="14" width="12.3" height="110" data-tip="2026-07-15|Cache read|379.7M tokens"/><rect class="seg m1" x="453.3" y="65.6" width="8.2" height="58.4" rx="2"/><rect class="hit" x="451.2" y="14" width="12.3" height="110" data-tip="2026-07-16|Cache read|530.8M tokens"/><rect class="seg m1" x="465.6" y="64.4" width="8.2" height="59.6" rx="2"/><rect class="hit" x="463.6" y="14" width="12.3" height="110" data-tip="2026-07-17|Cache read|541.5M tokens"/><rect class="seg m1" x="478.0" y="36.2" width="8.2" height="87.8" rx="2"/><rect class="hit" x="475.9" y="14" width="12.3" height="110" data-tip="2026-07-18|Cache read|798.5M tokens"/><rect class="seg m1" x="490.3" y="35.3" width="8.2" height="88.7" rx="2"/><rect class="hit" x="488.2" y="14" width="12.3" height="110" data-tip="2026-07-19|Cache read|806.1M tokens"/><rect class="seg m1" x="502.7" y="36.8" width="8.2" height="87.2" rx="2"/><rect class="hit" x="500.6" y="14" width="12.3" height="110" data-tip="2026-07-20|Cache read|793.1M tokens"/><rect class="seg m1" x="515.0" y="20.8" width="8.2" height="103.2" rx="2"/><rect class="hit" x="513.0" y="14" width="12.3" height="110" data-tip="2026-07-21|Cache read|938.3M tokens"/><rect class="seg m1" x="527.4" y="97.9" width="8.2" height="26.1" rx="2"/><rect class="hit" x="525.3" y="14" width="12.3" height="110" data-tip="2026-07-22|Cache read|237.1M tokens"/><rect class="seg m1" x="539.7" y="75.3" width="8.2" height="48.7" rx="2"/><rect class="hit" x="537.6" y="14" width="12.3" height="110" data-tip="2026-07-23|Cache read|442.6M tokens"/><text class="tick" x="58.1" y="140" text-anchor="start">May 20</text><text class="tick" x="547.9" y="140" text-anchor="end">Jul 23</text></svg></figure>
    </div>
  </div>
</div>

<h3>Model usage</h3>

<div class="rpt">
<div class="card"><div class="donut-wrap"><svg viewBox="0 0 260 260" class="chart donut" role="img" aria-label="Share of input plus output tokens by model"><path class="seg m1" d="M 131.15 34.01 A 96 96 0 1 1 45.58 175.71 L 75.48 159.52 A 62 62 0 1 0 130.74 68.00 Z" data-tip="Opus 4.8|48.2M tokens|67.3% of in+out"/><path class="seg m2" d="M 44.51 173.67 A 96 96 0 0 1 44.87 85.62 L 75.02 101.34 A 62 62 0 0 0 74.79 158.20 Z" data-tip="Opus 4.7|11.1M tokens|15.5% of in+out"/><path class="seg m3" d="M 45.96 83.59 A 96 96 0 0 1 118.08 34.74 L 122.30 68.48 A 62 62 0 0 0 75.73 100.03 Z" data-tip="Fable 5|11M tokens|15.4% of in+out"/><path class="seg m4" d="M 119.81 34.54 A 96 96 0 0 1 121.59 34.37 L 124.57 68.24 A 62 62 0 0 0 123.42 68.35 Z" data-tip="Haiku 4.5|353K tokens|0.5% of in+out"/><path class="seg m5" d="M 123.33 34.23 A 96 96 0 0 1 128.83 34.01 L 129.24 68.00 A 62 62 0 0 0 125.69 68.15 Z" data-tip="Kimi K3|926.7K tokens|1.3% of in+out"/><path class="seg m6" d="M 129.98 34.00 A 96 96 0 0 1 130.00 34.00 L 130.00 68.00 A 62 62 0 0 0 129.99 68.00 Z" data-tip="Sonnet 5|2.66K tokens|0.0% of in+out"/><text class="donut-v" x="130" y="128" text-anchor="middle">71.6M</text><text class="donut-l" x="130" y="147" text-anchor="middle">in + out tokens</text></svg><ul class="dlegend"><li><span class="sw m1"></span><span class="nm">Opus 4.8</span><span class="vl">48.2M</span><span class="pc">67.3%</span></li><li><span class="sw m2"></span><span class="nm">Opus 4.7</span><span class="vl">11.1M</span><span class="pc">15.5%</span></li><li><span class="sw m3"></span><span class="nm">Fable 5</span><span class="vl">11M</span><span class="pc">15.4%</span></li><li><span class="sw m4"></span><span class="nm">Haiku 4.5</span><span class="vl">353K</span><span class="pc">0.5%</span></li><li><span class="sw m5"></span><span class="nm">Kimi K3</span><span class="vl">926.7K</span><span class="pc">1.3%</span></li><li><span class="sw m6"></span><span class="nm">Sonnet 5</span><span class="vl">2.66K</span><span class="pc">&lt;0.1%</span></li></ul></div></div>
</div>

<div class="rpt wide">
<details class="tbl" open><summary>Table view — per model</summary>
    <div class="scroll"><table class="dt"><thead><tr><th scope="col">Model</th><th scope="col">User turns</th><th scope="col">API turns</th><th scope="col">Input</th><th scope="col">Output</th><th scope="col">Cache read</th><th scope="col">Cache write</th><th scope="col">Est. cost</th></tr></thead><tbody><tr><th scope="row"><i class="sw m1"></i>Opus 4.8</th><td>1418</td><td>31,683</td><td>2.02M</td><td>46.2M</td><td>11.5B</td><td>152.7M</td><td class="tot">$7,887</td></tr><tr><th scope="row"><i class="sw m2"></i>Opus 4.7</th><td>424</td><td>8,054</td><td>307.3K</td><td>10.8M</td><td>2.63B</td><td>40.9M</td><td class="tot">$1,840</td></tr><tr><th scope="row"><i class="sw m3"></i>Fable 5</th><td>275</td><td>10,531</td><td>1.07M</td><td>9.94M</td><td>4.05B</td><td>37.3M</td><td class="tot">$5,018</td></tr><tr><th scope="row"><i class="sw m4"></i>Haiku 4.5</th><td>0</td><td>1,383</td><td>18.9K</td><td>334.1K</td><td>64.5M</td><td>2.59M</td><td class="tot">$11.37</td></tr><tr><th scope="row"><i class="sw m5"></i>Kimi K3</th><td>16</td><td>274</td><td>763.4K</td><td>163.3K</td><td>70.5M</td><td>0</td><td class="tot">n/a</td></tr><tr><th scope="row"><i class="sw m6"></i>Sonnet 5</th><td>7</td><td>12</td><td>24</td><td>2.64K</td><td>5M</td><td>425.7K</td><td class="tot">$3.14</td></tr></tbody></table></div>
  </details>
</div>

<h2>Where does the human fit in?</h2>

My subjective feelings were that I had just as much cognitive load--if not more--than writing code without any AI. The shape of that load was different though. When writing code, the difficulty stems from trying to keep track of all the moving pieces in my head and trying to convert these abstract ideas into concrete code. The most rewarding feeling is seeing the code work after hours or days of coding. For this project, I have not written a single line of code myself. However it is still the same feeling of having these abstract ideas and trying to guide the AI into producing something that *feels* correct. A lot of the work is in reading the code and in debugging issues (just like before). Once a part is complete and I read the code and it looks *good* and I run it and it *works*, I get the same feeling of satisfaction.

<h3>The shape of it · One person, 59,443 words, 45,893 tool calls</h3>
<p class="lead">Over nine weeks of bringing up a Direct3D 11 driver stack across QEMU, virglrenderer, Mesa, a Windows WDDM kernel driver and a Metal backend, the human typed <strong>1,576 messages totalling 59,443 words</strong> — about 120 paperback pages. The models answered with <strong>101,031 messages</strong>, 45,893 tool calls, 67.4M output tokens and roughly <strong>1.84 million words</strong> of prose.</p>
<p>That is a 31:1 ratio of model words to human words. Put differently: <strong>every word the human typed bought about 0.77 tool calls</strong>, and every hour of model work cost about 125 human words.</p>
<div class="rpt">
<div class="tiles">
  <div class="tile"><div class="v">1,576</div><div class="l">human messages</div><div class="s">over 35 active days</div></div>
  <div class="tile"><div class="v">20</div><div class="l">median words per message</div><div class="s">mean 38</div></div>
  <div class="tile"><div class="v">8</div><div class="l">median tool calls bought</div><div class="s">mean 27, max 554</div></div>
  <div class="tile"><div class="v">8.8%</div><div class="l">of turns were “continue”</div><div class="s">or a status poll</div></div>
</div>
</div>
<div class="rpt wide">
<figure>
  <p class="ftitle">Engaged time splits about 1:7</p>
  <p class="fsub">553 hours of engaged clock time — every gap over 5 minutes discarded as idle — divided by which side of the loop the interval belongs to.</p>
  <div class="legend">
    <span class="lg"><i class="key" style="background:var(--s1)"></i>Human reading, thinking, typing <b>64.8 h · 11.7%</b></span>
    <span class="lg"><i class="key" style="background:var(--s2)"></i>Model working <b>476.3 h · 86.1%</b></span>
    <span class="lg"><i class="key" style="background:var(--muted)"></i>Other <b>12.2 h · 2.2%</b></span>
  </div>
  <svg viewBox="0 0 800 44" role="img" aria-label="Stacked bar: human-side 64.8 hours (11.7%), model-side 476.3 hours (86.1%), other 12.2 hours (2.2%)">
    <rect x="0" y="5" width="92" height="34" rx="4" fill="var(--s1)"/>
    <rect x="94" y="5" width="686" height="34" rx="4" fill="var(--s2)"/>
    <rect x="782" y="5" width="18" height="34" rx="4" fill="var(--muted)"/>
  </svg>
  <p class="fsub" style="margin:14px 0 0">The human's 64.8 hours are not leisure — they are the read-the-diff, form-the-hypothesis, write-the-next-instruction hours. Median wait between the model finishing and the human replying: 2.3 minutes. In a quarter of cases, under 50 seconds.</p>
  <figcaption>Intervals ending in a human message are attributed to the human; intervals of model activity to the model. Capping gaps at 5 minutes prevents overnight runs from swamping the ratio.</figcaption>
</figure>
</div>

This is the clearest evidence for what I said at the beginning: the tools allow you to amplify your existing skills. In this case, ~60 hours of human work amounted to ~480 hours of machine work.

<h3>Finding 1 · It is not a continue button</h3>
<p>The cheapest story about AI-assisted engineering is that the human degenerates into a keystroke: <em>continue, go ahead, yes, ship it.</em> The transcripts say otherwise, and they say it precisely — because “continue” is a short, exact string that can be counted.</p>
<p>Of 1,576 human messages, <strong>138 carried no new information</strong>: 88 pure continuations (<code>continue</code>, <code>yes</code>, <code>go ahead</code>, <code>keep going</code>), 36 status polls (<code>ping</code>, <code>any updates?</code>, <code>is it done?</code>) and 14 arbitrations where the human picked among options the model had laid out (<code>try option 1</code>, <code>let's do B1+B2</code>). That is <strong>8.8%</strong>. The remaining <strong>91.2% carried content</strong>, and they carried 99.5% of the words.</p>
<div class="rpt wide">
<figure>
  <p class="ftitle">How long is a human message?</p>
  <p class="fsub">Word count per message, all 1,576. The distribution’s centre of mass is a paragraph, not a keystroke.</p>
  <svg viewBox="0 0 800 250" role="img" aria-label="Column chart of human message lengths by word bucket: 1-3 words 153, 4-8 words 206, 9-20 words 443, 21-50 words 461, 51-100 words 193, 101-250 words 102, over 250 words 18">
    <line class="gridline" x1="46" y1="30" x2="800" y2="30"/>
    <line class="gridline" x1="46" y1="70" x2="800" y2="70"/>
    <line class="gridline" x1="46" y1="110" x2="800" y2="110"/>
    <line class="gridline" x1="46" y1="150" x2="800" y2="150"/>
    <text class="ax" x="0" y="34">500</text>
    <text class="ax" x="0" y="74">375</text>
    <text class="ax" x="0" y="114">250</text>
    <text class="ax" x="0" y="154">125</text>
    <text class="ax" x="0" y="194">0</text>
    <line class="baseline" x1="46" y1="190" x2="800" y2="190"/>
    <!-- scale: 500 -> 160px, so y = 190 - n*0.32 ; bar width 24 max, band 107 -->
    <rect x="70"  y="141.0" width="24" height="49.0"  rx="4" fill="var(--s1)"/>
    <rect x="178" y="124.1" width="24" height="65.9"  rx="4" fill="var(--s1)"/>
    <rect x="285" y="48.2"  width="24" height="141.8" rx="4" fill="var(--s1)"/>
    <rect x="393" y="42.5"  width="24" height="147.5" rx="4" fill="var(--s1)"/>
    <rect x="500" y="128.2" width="24" height="61.8"  rx="4" fill="var(--s1)"/>
    <rect x="608" y="157.4" width="24" height="32.6"  rx="4" fill="var(--s1)"/>
    <rect x="716" y="184.2" width="24" height="5.8"   rx="4" fill="var(--s1)"/>
    <text class="val" x="82"  y="134" text-anchor="middle">153</text>
    <text class="val" x="190" y="117" text-anchor="middle">206</text>
    <text class="val" x="297" y="41"  text-anchor="middle">443</text>
    <text class="val" x="405" y="35"  text-anchor="middle">461</text>
    <text class="val" x="512" y="121" text-anchor="middle">193</text>
    <text class="val" x="620" y="150" text-anchor="middle">102</text>
    <text class="val" x="728" y="177" text-anchor="middle">18</text>
    <text class="ax" x="82"  y="209" text-anchor="middle">1–3</text>
    <text class="ax" x="190" y="209" text-anchor="middle">4–8</text>
    <text class="ax" x="297" y="209" text-anchor="middle">9–20</text>
    <text class="ax" x="405" y="209" text-anchor="middle">21–50</text>
    <text class="ax" x="512" y="209" text-anchor="middle">51–100</text>
    <text class="ax" x="620" y="209" text-anchor="middle">101–250</text>
    <text class="ax" x="728" y="209" text-anchor="middle">250+</text>
    <text class="ax" x="405" y="234" text-anchor="middle">words per message</text>
  </svg>
  <figcaption>Only 153 messages are three words or fewer — and even inside that bucket sit things like <code>restore UNUSED</code>, <code>black</code>, and <code>drop d998f85e</code>, which are terse but not empty.</figcaption>
</figure>
</div>
<p>There is a twist worth noticing. When the human <em>did</em> just say “continue,” it bought <strong>more</strong> autonomous work than an average substantive message — a median of 15 tool calls against 7. “Continue” is not a filler turn; it is the specific instruction <em>keep grinding on the thing you already understand</em>, and it is issued precisely when the model already has enough context to grind.</p>

<h3>Finding 2 · Zero messages about how to use a tool</h3>
<p class="lead">Across 1,576 human messages there is not one instruction about search or file mechanics. No “grep for”, no “use ripgrep”, no “cat that file”, no “open the header”. Zero.</p>
<p>Meanwhile the models made 29,081 Bash calls, 6,293 edits, 5,968 reads and 1,048 writes. The entire mechanical layer of the work — deciding what to search, which VM to SSH into, which build script to run, where the log went — was never once specified.</p>
<p>What the human <em>does</em> specify is one level up, and it is remarkably consistent:</p>
<div class="rpt">
<div class="tblwrap">
<table>
  <thead><tr><th>The human’s actual vocabulary</th><th class="n">Messages</th><th class="n">Share</th></tr></thead>
  <tbody>
    <tr><td>Cites a specific git commit SHA (207 distinct SHAs)</td><td class="n">135</td><td class="n">8.6%</td></tr>
    <tr><td>Names a specific source file</td><td class="n">129</td><td class="n">8.2%</td></tr>
    <tr><td>Invokes MSDN / a spec / an API contract as ground truth</td><td class="n">66</td><td class="n">4.2%</td></tr>
    <tr><td>States a standing rule the model should carry forward</td><td class="n">97</td><td class="n">6.2%</td></tr>
    <tr><td class="hi">Tells the model how to search, read, or grep</td><td class="n hi">0</td><td class="n hi">0%</td></tr>
  </tbody>
</table>
</div>
</div>
<p>This is what “focusing on the big picture” looks like when you go measure it. The human’s register is commits, DDI entry points, render encoders, MSDN contracts and architectural trade-offs. The register of tool calls, file paths and shell invocations simply never appears — not because the human suppressed it, but because it never came up.</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span>“I want to understand a bit more how Triton’s swapchain implementation works. You have access to both the UMD, the KMD, and the host side Linux driver.”</div>
<div class="quote-src">2026‑07‑08</div>
</div>

"One level up" is a good way to put it. I have been thinking about how in the early days, people programmed in machine code. Then assembly code was invented to abstract away the encoding of instructions so human can focus on the semantics. Then higher level languages like C and Python were invented so humans can focus on the logical structure rather than the semantics. Now, with AI assistants, we can focus on the design and architecture rather than the logical structures.

<h3>Finding 3 · The model explains; the human decides</h3>
<p><strong>36.5% of substantive messages are questions or requests for explanation</strong> — 525 of 1,438. And these turns behave completely differently from the rest of the corpus.</p>
<div class="rpt">
<div class="tiles">
  <div class="tile"><div class="v">4</div><div class="l">median tool calls after a pure question</div><div class="s">vs 8 for all substantive turns</div></div>
  <div class="tile"><div class="v">2.6<span style="font-size:.55em"> min</span></div><div class="l">median duration of that run</div><div class="s">vs 4.0 min overall</div></div>
  <div class="tile"><div class="v">32%</div><div class="l">of question-runs touch code at all</div><div class="s">vs 63% after a data directive</div></div>
  <div class="tile"><div class="v">13.9%</div><div class="l">of all runs used zero tools</div><div class="s">235 pure conversations</div></div>
</div>
</div>
<p>Questions are cheap for the model and expensive in value for the human. They cost a couple of minutes, they mostly don’t touch code, and <strong>56% of the time the human’s very next message is a directive</strong> — the explanation gets converted straight into an instruction. The pattern is visible turn by turn: <code>ask → act</code> is 15.1% of all turn-to-turn transitions, almost exactly balanced against <code>act → ask</code> at 15.7%.</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span>“Do I understand the problem correctly as follows: DWM calls Present to D3D API but our UMD is not getting the DDI for the present? You mention 'dxgkrnl then does nothing at the KMD’ but I’m confused at how DWM talks to the KMD. It has to go through our UMD right? Can you map out for me the whole end to end call chain and where it’s not working?”</div>
<div class="quote user"><span class="who">User</span>“Can you explain a bit more why it spawned &gt; 48 swapchains? What is the sequence of calls from guest to host that caused it?”</div>
<div class="quote user"><span class="who">User</span>“I want to brainstorm a bit. Correct me where I’m wrong. So Triton requests N backbuffers for the swapchain → D3DMetal → our hooks → shmem allocation recorded by D3DMetal and virglrenderer…”</div>
<div class="quote-src">Three of the 525 explanation requests</div>
</div>
<p>The mechanism is worth naming, because it is the actual source of the human’s leverage. The human does not need to have read the 400,000 lines of VirtualBox, dxgkrnl, DXVK and D3DMetal in this project. They need a model that can read them on demand and explain the call chain — and then their own domain judgement is enough to say <em>that’s wrong, DXGI should already be limiting inflight frames, check the MSDN contract.</em> Explanation is what converts one person’s judgement into coverage over a codebase they could not otherwise hold in their head.</p>

I have found that AI models are much, *much*, better at understanding code than writing new code. Even if you are against using AI tools to write code (and that is an understandable position given how much work it is to properly review the code), you should be using it to understand new codebases.

<h3>Finding 4 · Reading the generated code is a job, and it has a measurable footprint</h3>
<p>Fourteen sessions open with an explicit protocol the human wrote, some version of: <em>“We will be doing an interactive code review. Each review item is either a question or a request for change. If it is a question, do not jump to changing the code.”</em></p>
<p>Those 14 sessions contain <strong>183 human messages against 2,626 tool calls — 14.3 tool calls per human turn</strong>. Everywhere else in the corpus the figure is <strong>31.1</strong>. Review mode is more than twice as human-dense as the rest of the work, and it eats about 25 engaged hours.</p>
<p>The extreme case is a rebase review on 2026‑05‑22: <strong>92 human messages, 566 tool calls — 6.2 tool calls per turn.</strong> That is a person going through a commit history line by line with a machine doing the typing.</p>
<div class="rpt wide">
<figure>
  <p class="ftitle">What each kind of human message buys</p>
  <p class="fsub">Median tool calls in the model run that immediately follows. The gradient runs from “explain something to me” up to “here is a plan and here is how to measure it.”</p>
  <svg viewBox="0 0 800 322" role="img" aria-label="Horizontal bar chart of median tool calls following each kind of human message: question 4, git hygiene 6, visual symptom only 8, review correction 8, continue 15, session-opening brief 17, data-collection directive 18, multi-step plan 25">
    <line class="gridline" x1="330" y1="8" x2="330" y2="290"/>
    <line class="gridline" x1="470" y1="8" x2="470" y2="290"/>
    <line class="gridline" x1="610" y1="8" x2="610" y2="290"/>
    <line class="gridline" x1="750" y1="8" x2="750" y2="290"/>
    <line class="baseline" x1="330" y1="8" x2="330" y2="290"/>
    <!-- x: 330 + n*16.8 ; rows 34px apart, bar height 18 -->
    <text class="lbl" x="322" y="26" text-anchor="end">Question / “explain this”</text>
    <rect x="330" y="12" width="67.2" height="18" rx="4" fill="var(--s1)"/>
    <text class="val" x="407" y="26">4</text>
    <text class="ax" x="430" y="26">n=421</text>
    <text class="lbl" x="322" y="60" text-anchor="end">Git / comment hygiene</text>
    <rect x="330" y="46" width="100.8" height="18" rx="4" fill="var(--s1)"/>
    <text class="val" x="441" y="60">6</text>
    <text class="ax" x="464" y="60">n=367</text>
    <text class="lbl" x="322" y="94" text-anchor="end">Visual symptom, no data ask</text>
    <rect x="330" y="80" width="134.4" height="18" rx="4" fill="var(--s2)"/>
    <text class="val" x="474" y="94">8</text>
    <text class="ax" x="497" y="94">n=91</text>
    <text class="lbl" x="322" y="128" text-anchor="end">Review / correction</text>
    <rect x="330" y="114" width="134.4" height="18" rx="4" fill="var(--s1)"/>
    <text class="val" x="474" y="128">8</text>
    <text class="ax" x="497" y="128">n=324</text>
    <text class="lbl" x="322" y="162" text-anchor="end">“continue”</text>
    <rect x="330" y="148" width="252" height="18" rx="4" fill="var(--s1)"/>
    <text class="val" x="592" y="162">15</text>
    <text class="ax" x="622" y="162">n=88</text>
    <text class="lbl" x="322" y="196" text-anchor="end">Session-opening brief</text>
    <rect x="330" y="182" width="285.6" height="18" rx="4" fill="var(--s1)"/>
    <text class="val" x="625" y="196">17</text>
    <text class="ax" x="655" y="196">n=187</text>
    <text class="lbl" x="322" y="230" text-anchor="end">Data-collection directive</text>
    <rect x="330" y="216" width="302.4" height="18" rx="4" fill="var(--s3)"/>
    <text class="val" x="642" y="230">18</text>
    <text class="ax" x="672" y="230">n=296</text>
    <text class="lbl" x="322" y="264" text-anchor="end">Multi-step ordered plan</text>
    <rect x="330" y="250" width="420" height="18" rx="4" fill="var(--s1)"/>
    <text class="val" x="760" y="264">25</text>
    <text class="ax" x="330" y="308" text-anchor="middle">0</text>
    <text class="ax" x="470" y="308" text-anchor="middle">8.3</text>
    <text class="ax" x="610" y="308" text-anchor="middle">16.7</text>
    <text class="ax" x="750" y="308" text-anchor="middle">25</text>
    <text class="ax" x="540" y="322" text-anchor="middle">median tool calls in the following run</text>
  </svg>
  <figcaption>Categories are keyword flags and overlap; a message can be both a correction and a data directive. Orange and green mark the pair discussed in Finding 5. <code>n</code> is the number of messages carrying that flag.</figcaption>
</figure>
</div>
<p>What review turns up is not stylistic. A sample from one three-hour session on virglrenderer:</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span>“question in f3ee46b4: in the change of <code>npt_context_import_resource</code> we removed the code for <code>close(fd)</code> then set <code>res-&gt;u.fd = fd</code>. When we have <code>VIRGL_RESOURCE_FD_SHM</code> does this not leak <code>res-&gt;u.data</code> in the union? this change was added in context of d3dmetal-native but is this change safe for all backends including dmabuf on linux?”</div>
<div class="quote user"><span class="who">User</span>“there is a change in <code>npt_cs.h</code> that is just an empty line. drop that change. also remember for the final pass to do the same in other commits as well.”</div>
<div class="quote user"><span class="who">User</span>“I don’t like the commit message. it doesn’t follow the rule of no development narrative. also: is it not possible to create both executables and lipo them? why does an external build have to be involved?”</div>
<div class="quote-src">2026‑07‑08 · 20 human messages, 212 tool calls, 3 hours</div>
</div>
<p>And the corrections land. In 1,576 messages there are only <strong>24 cases of the human having to repeat themselves</strong> to consecutive turns — 1.5%. Pointing at the problem is usually sufficient; the model does not generally need to be told twice what the fix is.</p>
<p>What it <em>does</em> need is emphasis. <strong>30.1% of human messages contain shouted words</strong> — ALWAYS, NOT, ONLY, NEVER, DO NOT — and the targets are consistent: don’t guess, don’t hand-wave, don’t push, don’t commit diagnostics, don’t stop.</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span>“I am not seeing ANY xperf runs. Why are you STILL making unfounded claims at this stage? ALWAYS COLLECT DATA FIRST”</div>
<div class="quote user"><span class="who">User</span>“DO NOT JUST HAND WAVE A STALL. ALWAYS DEBUG IT BECAUSE IT MAY SURFACE A REAL ISSUE”</div>
<div class="quote user"><span class="who">User</span>“A wedged VM is NOT normal and should be debugged instead of just cleaned up and put under the rug. Any time you hit an error, you should fix it. Do not be lazy.”</div>
</div>
<h3>Finding 5 · The expensive problem is that the model cannot see</h3>
<p class="lead">This project’s hardest bugs were visual: a black screen, a missing search pill in the Windows taskbar, glyphs that don’t render, a magenta tint over an aurora, frames that flash black at 30 Hz. The model has no eyes. For nine weeks, <strong>the human was the display.</strong></p>
<p><strong>139 messages</strong> are the human reporting what is on a screen the model cannot query. Read in date order they read like an instrument log, and the language sharpens over time:</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span><strong>May 28</strong> — “I do see the desktop after the driver load but it seems to have loaded one frame and the entire process is frozen”</div>
<div class="quote user"><span class="who">User</span><strong>Jul 4</strong> — “I see the calculator now but as I move the mouse cursor around, there are random artifacts that appear… once the mouse stops, after a few seconds, it refreshes and looks right again”</div>
<div class="quote user"><span class="who">User</span><strong>Jul 17</strong> — “I no longer notice the hangs but now we have a constant micro-stuttering. As GT1 runs, I constantly see flashes of black screen that feels like 1-2 frames of black. It is persistent through the entire run.”</div>
<div class="quote user"><span class="who">User</span><strong>Jul 23</strong> — “I see a completely black screen for 17 seconds. Then I see frame 801 stuck for the next few seconds. Then it terminates.”</div>
</div>
<p>That progression — from “frozen” to “1–2 frames of black” to “17 seconds, then frame 801” — <em>is</em> the work. The human is converting a perception into a quantity the model can go look for. Until that conversion happens, the model is guessing.</p>
<p>The transcripts contain the moment where this becomes explicit, and the human is blunt about it twice:</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span>“I don’t see anything on screen. How are you observing it? The instructions is that it must render to screen”</div>
<div class="quote-src">2026‑07‑04 — the model had claimed success it had no way to verify</div>
<div class="quote user"><span class="who">User</span>“I see a completely black screen. are you sure your monitor is working correctly?”</div>
<div class="quote-src">2026‑07‑06</div>
</div>
<div class="rpt callout-only">
<div class="callout wash">
  <p class="h">The measurable version</p>
  <p>A message reporting a <strong>visual symptom with no instruction about how to observe it</strong> buys a median of <strong>8 tool calls</strong>. A message that tells the model <strong>what to instrument, dump, trace or capture</strong> buys <strong>18</strong> — and runs 11.2 minutes instead of 7.4. Same human, same bugs, same models. The difference is whether the model has been handed a way to see.</p>
</div>
</div>

I do feel this is a problem that will be solved with better models.

<h4>Case study: the missing search pill</h4>
<p>On 2026‑07‑18 the human opened a session with a description of a rendering bug that had persisted “since day 1”: under the D3DMetal backend, the Windows desktop drops compositing layers. The Start menu is sometimes an empty box; the taskbar’s rounded search box renders as bare text on the bar. Twenty-seven human messages and 705 tool calls later, over fourteen hours, the shape of the human’s day is this:</p>
<div class="rpt wide">
<figure>
  <p class="ftitle">One visual bug, turn by turn</p>
  <p class="fsub">2026‑07‑18. Each column is one human message; height is the tool calls the model made before coming back. Fourteen hours, left to right.</p>
  <svg viewBox="0 0 800 336" role="img" aria-label="Column chart of 27 human turns in the 2026-07-18 session, showing tool calls per turn peaking at 191 on turn 19">
    <line class="gridline" x1="40" y1="40" x2="790" y2="40"/>
    <line class="gridline" x1="40" y1="88" x2="790" y2="88"/>
    <line class="gridline" x1="40" y1="136" x2="790" y2="136"/>
    <line class="gridline" x1="40" y1="184" x2="790" y2="184"/>
    <text class="ax" x="0" y="44">200</text>
    <text class="ax" x="0" y="92">150</text>
    <text class="ax" x="0" y="140">100</text>
    <text class="ax" x="0" y="188">50</text>
    <text class="ax" x="0" y="236">0</text>
    <line class="baseline" x1="40" y1="232" x2="790" y2="232"/>
    <!-- scale: 200 -> 192px  => y = 232 - n*0.96 ; 27 bands of 27.4px, bar 16 -->
    <rect x="46"  y="169.6" width="16" height="62.4" rx="4" fill="var(--s1)"/>
    <rect x="73"  y="232"   width="16" height="0.8"  rx="0" fill="var(--muted)"/>
    <rect x="101" y="230.1" width="16" height="1.9"  rx="2" fill="var(--muted)"/>
    <rect x="128" y="232"   width="16" height="0.8"  rx="0" fill="var(--muted)"/>
    <rect x="156" y="174.4" width="16" height="57.6" rx="4" fill="var(--s1)"/>
    <rect x="183" y="213.8" width="16" height="18.2" rx="4" fill="var(--s1)"/>
    <rect x="211" y="226.2" width="16" height="5.8"  rx="3" fill="var(--s1)"/>
    <rect x="238" y="192.6" width="16" height="39.4" rx="4" fill="var(--s3)"/>
    <rect x="266" y="230.1" width="16" height="1.9"  rx="2" fill="var(--s1)"/>
    <rect x="293" y="223.4" width="16" height="8.6"  rx="4" fill="var(--s1)"/>
    <rect x="321" y="228.2" width="16" height="3.8"  rx="3" fill="var(--s1)"/>
    <rect x="348" y="221.4" width="16" height="10.6" rx="4" fill="var(--s1)"/>
    <rect x="376" y="193.6" width="16" height="38.4" rx="4" fill="var(--s1)"/>
    <rect x="403" y="220.5" width="16" height="11.5" rx="4" fill="var(--s1)"/>
    <rect x="431" y="226.2" width="16" height="5.8"  rx="3" fill="var(--s1)"/>
    <rect x="458" y="218.6" width="16" height="13.4" rx="4" fill="var(--s1)"/>
    <rect x="486" y="229.1" width="16" height="2.9"  rx="2" fill="var(--s1)"/>
    <rect x="513" y="197.4" width="16" height="34.6" rx="4" fill="var(--s3)"/>
    <rect x="541" y="48.6"  width="16" height="183.4" rx="4" fill="var(--s3)"/>
    <rect x="568" y="188.8" width="16" height="43.2" rx="4" fill="var(--s3)"/>
    <rect x="596" y="216.6" width="16" height="15.4" rx="4" fill="var(--s1)"/>
    <rect x="623" y="221.4" width="16" height="10.6" rx="4" fill="var(--s1)"/>
    <rect x="651" y="184.0" width="16" height="48.0" rx="4" fill="var(--s2)"/>
    <rect x="678" y="229.1" width="16" height="2.9"  rx="2" fill="var(--s2)"/>
    <rect x="706" y="232"   width="16" height="0.8"  rx="0" fill="var(--s2)"/>
    <rect x="733" y="226.2" width="16" height="5.8"  rx="3" fill="var(--s2)"/>
    <rect x="761" y="229.1" width="16" height="2.9"  rx="2" fill="var(--s2)"/>
    <text class="val" x="549" y="42" text-anchor="middle">191</text>
    <!-- numbered markers, placed above their bars so nothing collides -->
    <circle cx="54"  cy="158" r="9" fill="var(--s1)"/>
    <text x="54"  y="162" text-anchor="middle" fill="#fff" font-size="11" font-weight="650">1</text>
    <circle cx="549" cy="34"  r="9" fill="var(--s3)"/>
    <text x="549" y="38"  text-anchor="middle" fill="#fff" font-size="11" font-weight="650">2</text>
    <circle cx="659" cy="172" r="9" fill="var(--s2)"/>
    <text x="659" y="176" text-anchor="middle" fill="#fff" font-size="11" font-weight="650">3</text>
    <text class="ax" x="46"  y="250">turn 1</text>
    <text class="ax" x="790" y="250" text-anchor="end">turn 28 · +13.8 h</text>
    <!-- annotation key, stacked below the axis -->
    <circle cx="52" cy="274" r="7" fill="var(--s1)"/>
    <text x="52" y="277.5" text-anchor="middle" fill="#fff" font-size="9.5" font-weight="650">1</text>
    <text class="anno" x="68" y="278">The symptom, described in prose. The model starts bisecting the wrong thing;
      turns 2–5 stop it, twice by interrupt.</text>
    <circle cx="52" cy="298" r="7" fill="var(--s3)"/>
    <text x="52" y="301.5" text-anchor="middle" fill="#fff" font-size="9.5" font-weight="650">2</text>
    <text class="anno" x="68" y="302">“Get the AIR of both sides and compare them.” 191 tool calls — then the human is gone
      for 6.5 hours.</text>
    <circle cx="52" cy="322" r="7" fill="var(--s2)"/>
    <text x="52" y="325.5" text-anchor="middle" fill="#fff" font-size="9.5" font-weight="650">3</text>
    <text class="anno" x="68" y="326">The human returns having dumped the render-encoder PNGs themselves,
      and pastes the Metal stack into the chat.</text>
  </svg>
  <figcaption>Green marks messages that specify data collection; orange marks the closing stretch where the human supplies the data themselves. The two flat bars at turns 2 and 4 are messages the model was interrupted on — the human hit escape and repeated itself.</figcaption>
</figure>
</div>
<p>The arc is the whole thesis in one day. It opens with the symptom described in words. The model immediately starts bisecting compiler workaround flags, and the human has to stop it — three times, twice by interrupt:</p>
<div class="quote user"><span class="who">User</span>“the workaround flags are DESIGNED for D3DMetal … you are wasting your time bisecting them; they are all proven to be required and this layer composite issue has persisted since day 1”</div>
<p>Then eighteen turns of hypothesis and small experiments — the 2DTextureArray view, <code>CheckFormatSupport</code>, whether DWM ever queries <code>D3D11_FEATURE_FORMAT_SUPPORT2</code> — mostly cheap runs of 2 to 40 tool calls. At turn 18 the human asks for the first real data channel: <em>“can you dump the DXBC → Metal shaders for each DXBC. try to find the one that composites the search pill. then compare the metal code for both.”</em> At turn 19 they escalate it to <em>“get the AIR of both sides and compare them”</em> — and the model runs 191 tool calls, then the human disappears for six and a half hours.</p>
<p>And then the ending, which is the part worth sitting with. The human comes back having done the observation work themselves:</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span>“Using the Metal dumps from earlier, I was able to narrow down to a command buffer that does the same work in both DXMT and D3DM which produced different results. Take a look in <code>dwm-render-debug</code>. I’ve dumped the PNG for each render encoder color 0 attachment output at the end of each render encoder. The last image shows the rendered taskbar. In DXMT, the taskbar is complete: clock, icons, search pill. In D3DM, it is missing many of those elements.”</div>
<div class="quote-src">Turn 24</div>
</div>
<p>Followed by pasting a raw Metal command stack into the chat — <em>“do you see the missing draws”</em> — and then, two turns later, explaining the file format to the model: <em>“each empty line separates a render encoder.”</em></p>
<p>The bottleneck was never the model’s reasoning. It was the absence of a channel between a pixel on a screen and a token the model could read. Building that channel took a human most of a day.</p>
<p>There is a second-order effect worth flagging: <strong>48% of a session’s human messages fall in the first third of its span.</strong> The human’s work is front-loaded, and the session-opening brief is the highest-leverage thing they write — a median 52 words against 18 for later turns, buying 17 median tool calls against 8. Roughly half the messages in a session are spent aiming it.</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span>“this reveals one of the previous failure modes. I see many flashes of completely black frames (1/2 of frames rendered). but no frozen frame or stuck black. <strong>Also: I cannot sit here and watch the whole thing.</strong>”</div>
<div class="quote-src">2026‑07‑23 — the constraint, named</div>
</div>

Once I was able to get the AI to empirically measure the failure and set a goal to fix that metric, the hard work is "done" and the rest can be automated.

<h3>Finding 6 · The human compiled their own continue button</h3>
<p>Because they could not sit there and watch, they wrote down what “done” means and made the harness enforce it. Across the corpus there are <strong>49 distinct <code>/goal</code> conditions</strong> — success predicates registered as stop-hooks — that fired <strong>395 times</strong>. Of those, <strong>367 fires blocked the model from ending its turn.</strong></p>
<p>Three hundred and sixty-seven times, the model tried to stop and a sentence the human had written earlier pushed it back in. That is the “continue” key, turned into a spec.</p>
<div class="rpt">
<div class="tblwrap">
<table>
  <thead><tr><th>Goal condition (abridged)</th><th class="n">Fires</th><th class="n">Blocked</th></tr></thead>
  <tbody>
    <tr><td>“Figure out the difference between DXMT and D3DMetal in pill rendering… Keep going until you figure out why the pill is not rendered, confirm it, patch in a fix, and test that it works.”</td><td class="n">56</td><td class="n">56</td></tr>
    <tr><td>“Fix all the P1 items. Make sure to follow the same pattern: validate API calls with MSDN documentation, cross-check against virtualbox, and commit without narrative comments”</td><td class="n">48</td><td class="n">48</td></tr>
    <tr><td>“Fix all three issues… Make sure the VM can run for 15 minutes without crashing or going out of memory while maintaining visible scanouts.”</td><td class="n">35</td><td class="n">35</td></tr>
    <tr><td>“fix the black screen”</td><td class="n">35</td><td class="n">34</td></tr>
    <tr><td>“Achieve &gt; 5000 on 3dmark firestrike”</td><td class="n">23</td><td class="n">23</td></tr>
  </tbody>
</table>
</div>
</div>
<p>What is striking is not the goals that name an outcome. It is how many of them name a <em>method</em>. The human is not only specifying what done looks like — they are specifying the epistemics:</p>
<div class="exchange">
<div class="quote user"><span class="who">User</span>“Keep doing whatever it takes to track down the issue. ALWAYS collect data first and back up hypothesis by evidence. Do not make any assumptions. Do not use process of elimination. Do not give up and declare the issue preexisting or because of environmental issues. Figure out why frames are stuck. Keep adding logging until you get a clear picture. Attempt a fix and validate by seeing the data change.”</div>
<div class="quote user"><span class="who">User</span>“Triage and fix the channel swap bug. Fix is validated when you observe the correct channel values with your diagnostics.”</div>
<div class="quote user"><span class="who">User</span>“Fix the black frames issue. First add additional diagnostics in order to help you triage. Then attempt a fix. Goal is not complete until you demonstrate an entire Fire Strike run is free of black flashes.”</div>
<div class="quote-src">Three of the 49 goal conditions</div>
</div>
<p>And separately, typed into the conversation as a standing instruction:</p>
<div class="quote user"><span class="who">User</span>“always do diagnostic first; collect as much data as possible to guide you towards the best solution. then when writing the solution, always make a proper one that addresses the issue fully. no half-baked ideas. no workarounds or hacks. this is production code. <strong>do not prompt me for guidance unless you cannot follow these rules.</strong>”</div>
<p>That last clause is the human explicitly pricing their own attention.</p>
<h3>Finding 7 · Less hand-holding, quantified</h3>

I felt that Fable 5 required a lot less babysitting than Opus 4.8. Here is the data to back it up.

<p>The corpus spans three model generations on overlapping work, which makes “this one needed less babysitting” a testable claim rather than an impression. It holds.</p>
<div class="rpt">
<div class="tblwrap">
<table>
  <thead><tr><th>Model</th><th class="n">Runs</th><th class="n">Median tools</th><th class="n">Mean</th><th class="n">p90</th><th class="n">Median run</th><th class="n">Interrupted</th></tr></thead>
  <tbody>
    <tr><td class="hi">Fable 5</td><td class="n">222</td><td class="n hi">17</td><td class="n">53.8</td><td class="n">152</td><td class="n">9.1 min</td><td class="n hi">14.4%</td></tr>
    <tr><td>Opus 4.8</td><td class="n">1,109</td><td class="n">8</td><td class="n">24.0</td><td class="n">63</td><td class="n">5.1 min</td><td class="n">22.3%</td></tr>
    <tr><td>Opus 4.7</td><td class="n">253</td><td class="n">6</td><td class="n">27.5</td><td class="n">92</td><td class="n">2.5 min</td><td class="n">12.6%</td></tr>
  </tbody>
</table>
</div>
</div>
<p>Model choice was not randomised, so the honest check is within-project, where the task mix is at least comparable:</p>
<div class="rpt">
<div class="tblwrap">
<table>
  <thead><tr><th>Repository</th><th class="n">Fable 5 median</th><th class="n">Opus 4.8 median</th></tr></thead>
  <tbody>
    <tr><td>Neptune-QEMU</td><td class="n hi">21 <span class="ax">(n=94)</span></td><td class="n">9 <span class="ax">(n=445)</span></td></tr>
    <tr><td>VMs (driver bring-up)</td><td class="n hi">16 <span class="ax">(n=48)</span></td><td class="n">11 <span class="ax">(n=220)</span></td></tr>
    <tr><td>kvm-guest-drivers-windows</td><td class="n hi">19 <span class="ax">(n=7)</span></td><td class="n">7 <span class="ax">(n=50)</span></td></tr>
    <tr><td>dxmt</td><td class="n hi">38 <span class="ax">(n=4)</span></td><td class="n">5 <span class="ax">(n=17)</span></td></tr>
    <tr><td>d3dmetal-native</td><td class="n">6 <span class="ax">(n=49)</span></td><td class="n hi">14 <span class="ax">(n=31)</span></td></tr>
  </tbody>
</table>
</div>
</div>
<p>Four of five go the same way, one goes the other. The two longest unattended runs in the entire corpus are both Fable: <strong>554 tool calls over 6 hours</strong> and <strong>541 tool calls over 13.5 hours</strong>, each launched by a single human message.</p>
<p>The “but I still have to step in” half is equally visible: <strong>one Fable run in seven was interrupted by the human hitting escape</strong>. Across all models it is 19.0% — 321 runs, 334 interrupt events. Roughly one intervention every five turns, all corpus long, at every model generation.</p>
<h3>Finding 8 · The human got more involved over time, not less</h3>
<p class="lead">This is the result that runs against the intuition, and it is not an artefact of session count — it survives normalising by engaged hours.</p>
<div class="rpt wide">
<figure>
  <p class="ftitle">Human messages per engaged hour, by project phase</p>
  <p class="fsub">Model tool calls per engaged hour stayed flat across the same period (77 → 85). The human’s rate doubled.</p>
  <svg viewBox="0 0 800 280" role="img" aria-label="Column chart: human messages per engaged hour rose from 1.86 in late May to 2.64 in early July to 3.67 in late July">
    <line class="gridline" x1="60" y1="30" x2="790" y2="30"/>
    <line class="gridline" x1="60" y1="74" x2="790" y2="74"/>
    <line class="gridline" x1="60" y1="118" x2="790" y2="118"/>
    <line class="gridline" x1="60" y1="162" x2="790" y2="162"/>
    <text class="ax" x="0" y="34">4.0</text>
    <text class="ax" x="0" y="78">3.0</text>
    <text class="ax" x="0" y="122">2.0</text>
    <text class="ax" x="0" y="166">1.0</text>
    <text class="ax" x="0" y="210">0</text>
    <line class="baseline" x1="60" y1="206" x2="790" y2="206"/>
    <!-- scale 4.0 -> 176px => y = 206 - v*44 -->
    <rect x="140" y="124.2" width="24" height="81.8" rx="4" fill="var(--s1)"/>
    <rect x="380" y="89.8"  width="24" height="116.2" rx="4" fill="var(--s1)"/>
    <rect x="620" y="44.5"  width="24" height="161.5" rx="4" fill="var(--s1)"/>
    <text class="val" x="152" y="116" text-anchor="middle">1.86</text>
    <text class="val" x="392" y="82"  text-anchor="middle">2.64</text>
    <text class="val" x="632" y="37"  text-anchor="middle">3.67</text>
    <text class="lbl" x="152" y="228" text-anchor="middle">late May</text>
    <text class="ax"  x="152" y="245" text-anchor="middle">Windows bring-up</text>
    <text class="ax"  x="152" y="260" text-anchor="middle">147 engaged h · 273 msgs</text>
    <text class="lbl" x="392" y="228" text-anchor="middle">early July</text>
    <text class="ax"  x="392" y="245" text-anchor="middle">macOS bring-up</text>
    <text class="ax"  x="392" y="260" text-anchor="middle">188 engaged h · 497 msgs</text>
    <text class="lbl" x="632" y="228" text-anchor="middle">late July</text>
    <text class="ax"  x="632" y="245" text-anchor="middle">correctness + perf</text>
    <text class="ax"  x="632" y="260" text-anchor="middle">214 engaged h · 787 msgs</text>
  </svg>
  <figcaption>June is omitted — only 4 sessions and 4 engaged hours, too thin to plot. Engaged hours count only intervals under 5 minutes, so overnight autonomous runs do not inflate the denominator.</figcaption>
</figure>
</div>
<p>Over the same period the mix of what the human was saying shifted decisively. The share of messages carrying a data-collection instruction went from <strong>9% to 24%</strong>. Tool calls bought per human message fell from 39 to 24.</p>
<p>The explanation is in the nature of the work, not the quality of the models. Late May was greenfield: <em>make anything appear on the screen.</em> That is a goal you can state in one sentence and walk away from — and the human did, at 1.86 messages per hour. Late July was <em>make the taskbar composite correctly, eliminate the 40% black-frame rate, get Present off the critical path, and clean the commit history for upstream.</em> Those are goals where the human is the oracle for whether it worked, the reviewer of every line that ships, and the designer of the measurement.</p>
<div class="rpt callout-only">
<div class="callout wash">
  <p class="h">The pattern</p>
  <p>Autonomy is highest when the goal is coarse and failure is obvious. It drops exactly where the work gets valuable — where “correct” is a judgement call, where the evidence is a pixel, and where the code has to be good enough for someone else to merge.</p>
</div>
</div>

This makes sense because the initial bring-up phase was mostly just guiding the AI into a good design. The debug (correctness and performance) phase required a lot more intervention due to the previously stated difficulties.

<h3>So, where? · The human is the part that cannot be delegated because it touches the world</h3>
<p>Reading nine weeks of this backwards, the human’s residual job sorts into four things, and none of them is writing code:</p>
<ul>
  <li><strong>Perception.</strong> The model cannot see the screen, hear the fan, or feel that the cursor lags. 139 messages exist purely to carry a perception across that gap, and the hardest single day in the corpus was spent building a pipe so the model could see one taskbar.</li>
  <li><strong>Judgement about what “correct” means.</strong> 49 goal predicates, 97 standing rules, 66 appeals to a spec, and an interactive review protocol the human wrote and ran fourteen times. The model can check a program against a rule; someone has to author the rule.</li>
  <li><strong>Decomposition and altitude.</strong> The session-opening brief is the single highest-leverage artefact in the corpus — 3× longer than an average message and buying 2× the autonomous work. Zero of 1,576 messages descend to tool mechanics.</li>
  <li><strong>Being the world’s actuator.</strong> Rebooting the host, restarting the VM, and telling the model what happened.</li>
</ul>
<p>The volumes are worth restating plainly. The human spent about <strong>65 engaged hours</strong> on the loop across nine weeks and produced <strong>59,443 words</strong>. The models spent <strong>476 hours</strong> and produced 1.84 million words plus 45,893 tool calls. The leverage is roughly 7:1 in time and 31:1 in output.</p>
<p>But the leverage is not free and it is not increasing. Over the nine weeks the human’s rate of input <em>doubled</em> — because the work moved from “make it render” to “make it render correctly,” and correctness is exactly the region where the model needs a person to be the eyes, the spec, and the reviewer. The bottleneck did not disappear. It migrated, from typing to seeing.</p>

<h2>Appendix: one bug, three models</h2>

<p>One entry in that timeline supports a comparison the rest of the project does not. Present-gate pipelining — the second-to-last milestone, 21–23 July — was worked by three different models on three consecutive days, two of them from a verbatim-identical opening prompt. The next part compares them at equal token spend. It is not a benchmark, and the fairness ledger below matters more than the headline; but it is a rare look at what “needs less hand-holding” means when it is counted rather than felt.</p>

When Kimi K3 came out, many people online claimed it was as good as Fable 5 so I was curious to test the claim out. This analysis is not a fair comparison of capability because I limited my Moonshot token spend to $30 but I think what the model did with that $30 is an interesting story to read.

<h3>The three sessions</h3>

<p class="lede-prose">All three ran on the same machine against, driving the same Windows-on-aarch64 guest through the same <code>nept.py</code> harness.</p>

<div class="rpt wide">
<div class="scroll">
  <table class="dt">
    <thead><tr>
      <th></th><th>Opus 4.8</th><th>Kimi K3</th><th>Fable 5</th>
    </tr></thead>
    <tbody>
      <tr><th>Session</th>
        <td><code>a0816380</code></td><td><code>d8f976e3</code></td>
        <td><code>ff50fe7a</code>&nbsp;→&nbsp;<code>daff6027</code></td></tr>
      <tr><th>Model phase</th>
        <td>Jul&nbsp;21 11:05 → Jul&nbsp;22 09:58</td>
        <td>Jul&nbsp;22 11:58 → 15:11</td>
        <td>Jul&nbsp;23 00:20 → 18:14</td></tr>
      <tr><th>Wall clock</th><td class="n">22.9 h</td><td class="n">3.21 h</td><td class="n">17.9 h</td></tr>
      <tr><th>Active time <span style="color:var(--muted)">(gaps ≤5 min)</span></th>
        <td class="n">13.9 h</td><td class="n"><b>2.90 h</b></td><td class="n">5.71 h</td></tr>
      <tr><th>API responses</th><td class="n">1,128</td><td class="n">274</td><td class="n">611</td></tr>
      <tr><th>Tool calls</th><td class="n">1,101</td><td class="n">301</td><td class="n">599</td></tr>
      <tr><th>Output tokens</th><td class="n">1,798,997</td><td class="n">163,274</td><td class="n">612,249</td></tr>
      <tr class="hi"><th>Billed tokens</th>
        <td class="n">533.1 M</td><td class="n"><b>71.4 M</b></td><td class="n">322.0 M</td></tr>
      <tr><th>Spend</th>
        <td class="n">$339 <span style="color:var(--muted)">list</span></td>
        <td class="n"><b>$30</b> <span style="color:var(--muted)">hard cap</span></td>
        <td class="n">$392 <span style="color:var(--muted)">list</span></td></tr>
      <tr><th>Ended because</th>
        <td>user asked for cleanup + handoff</td>
        <td><code>429 · insufficient balance</code></td>
        <td>user exited after a regression check</td></tr>
    </tbody>
  </table>
  </div>
</div>

<div class="rpt callout-only">
<div class="callout">
    Kimi K3 consumed <b>71.4 M billed tokens</b> — 763 K uncached input, 163 K output,
    70.5 M cache reads, zero cache writes. That number is the yardstick for everything below.
  </div>
</div>

<h3>The problem all three inherited</h3>

<p class="lede-prose">A paravirtual WDDM driver stack: guest UMD (<code>virtio-win-mesa</code>, the Triton D3D11 driver) → KMD (<code>kvm-guest-drivers-windows</code>) → virtio → host <code>virglrenderer</code> → QEMU cocoa → Metal. Present was blocking the app thread while the GPU worked, so CPU and GPU never overlapped: 3DMark Fire Strike GT1 ran at ~27 fps with the render thread parked inside <code>Present</code>.</p>

<p class="lede-prose">Removing the block unlocked pipelining and broke correctness. The user’s opening prompt — <em>identical, verbatim, to Kimi and to Fable</em> — named three failure modes and told the model to distrust every prior conclusion:</p>

<div class="rpt">
<div class="card note">
    <p><em>“…audit the code at HEAD (KMD+UMD) focusing on the events, fencing, and present
    architecture… Then build and test the driver and try to detect the different failure modes
    we’ve observed: <b>1)</b> flashing black frames (likely inert fences → present before frame is
    ready), <b>2)</b> stuck frames (likely stuck fences → present gets blocked in the pipe), and
    <b>3)</b> underutilized GPU (due to lack of pipelining). The existing test and diagnostics the
    last agent produced is incomplete.”</em></p>
    <p style="margin-bottom:0">Opus 4.8’s prompt the previous day was different in form — it began
    from <code>HANDOFF-perf-analysis-methodology.md</code> and asked for triage and a diagnostic
    A/B path rather than an audit of a specific HEAD.</p>
  </div>
</div>

<h3>Was Kimi K3 going in the right direction?</h3>

<p class="lede-prose">Mostly yes. Its progress report at 13:43 made ten checkable claims. Six hold up against everything measured afterwards, two are correct for the exact tree it audited, and two are wrong — one of them badly, because it closed off the failure mode the user had explicitly asked about.</p>

<div class="rpt wide">
<div class="scroll">
  <table class="dt">
    <thead><tr><th style="min-width:30ch">Kimi’s claim</th><th style="width:1%">Verdict</th><th>Adjudicated by</th></tr></thead>
    <tbody>
      <tr><td>Failure mode 3 (GPU underutilisation) is <b>already fixed</b> at HEAD — overlap index ≈1.1, GT1 50.2 fps DXMT / 77.6 D3DMetal vs the 27.2 fps blocking baseline</td>
        <td class="v y">Right</td>
        <td>Fable measured overlap ≈1.0 on the same HEAD independently the next morning</td></tr>
      <tr><td>The broken piece is the <b>association</b> between a fence arm and the flip it gates — flips run un-gated (<code>tok=0</code>) → black/torn frames</td>
        <td class="v y">Right</td>
        <td>Fable’s independent audit reached the same conclusion and proved it live: <code>NPT-DIAG promote tok=0 done=145 zero=129 nonzero=0</code>. The fix that finally shipped, <code>5d984dc3</code>, is a token-association fix</td></tr>
      <tr><td>The mechanism is the <b>16-slot pid-keyed token table</b> exhausting after 16 presenter pids, then dropping silently</td>
        <td class="v p">Right for its tree</td>
        <td>True of HEAD + the 736 uncommitted lines Kimi audited. At <i>clean</i> HEAD the mechanism is different — the escape lands on the npt transport’s own private <code>D3DKMT</code> device, so every flip reads 0 from the first frame. Both are correct; they audited different trees</td></tr>
      <tr><td>A <b>per-device stamp via a user-mode <code>D3DKMT</code> handle is impossible</b>: <code>VioGpuDevice::FromHandle</code> calls a virtual <code>Magic()</code> on a foreign pointer, and <code>DXGK_HANDLE_TYPE</code> only has ALLOCATION and RESOURCE</td>
        <td class="v y">Right</td>
        <td>Kimi built it, bugchecked the guest with 0xFC, and diagnosed why. Recorded as do-not-retry and never revisited by anyone. This is its most durable contribution</td></tr>
      <tr><td>The fix is <b>one adapter-global monotonic token</b>, peeked by the flip at latch time</td>
        <td class="v p">Adopted, then killed</td>
        <td>Fable shipped precisely this as <code>b2b04618</code>, then proved it livelocks a pipelined app — at depth 3 with steady frame times flip <i>N</i>+1 always latches before token <i>N</i> retires, so each new latch replaces the almost-ready one. Reverted, then dropped from history</td></tr>
      <tr><td>Its own follow-on redesign: <b>contiguous-prefix retirement</b>, so <code>done ≥ T</code> implies every token ≤ <i>T</i> retired</td>
        <td class="v n">Unsound</td>
        <td>Completions aren’t 1:1 with arms in token order (<code>PFENCE-ARM #5632 token=5632</code> vs <code>PFENCE-CB #5632 token=5730</code>, <code>wrap=72</code>), so the walk wedges permanently — <code>done</code> frozen at 651 while flips asked for 2822. Caught by Opus 4.8 <b>1h58m after Kimi’s budget died</b>; Kimi never compiled it</td></tr>
      <tr><td>Stuck frames are <b>not</b> stuck fences — the 2–4 s mid-GT1 gaps are app-side guest CPU</td>
        <td class="v y">Right</td>
        <td>Fable’s 51-second guest ETW trace: the frame-producing thread is 92–100% on-CPU straight through the hitch window, waits ≤8%, disk utilisation ≤30% — single-threaded asset ingest inside the statically-linked exe</td></tr>
      <tr><td>The 30–60 s freezes are <b>an idle desktop with no presents — benign</b></td>
        <td class="v n">Wrong</td>
        <td>The multi-second frozen frame was real and had two driver causes, both fixed later: FlipThread vsync starvation (every fence-completion wake restarted the vsync period, and MMIO-flip completion is reported <i>only</i> by the CRTC_VSYNC interrupt — a 1123 ms present stall was measured), and unbounded CPU run-ahead (every token in the flip queue seconds from retiring → 5–15 scanouts/s). Fable found the vsync bug in its first 46 minutes</td></tr>
      <tr><td>The <code>VIOGPU_GET_GATE_STATS</code> escape the old probe expects no longer exists in the KMD</td>
        <td class="v y">Right</td>
        <td>Fable later re-implemented it as a diagnostic patch</td></tr>
      <tr><td>Two stale claims corrected: the KMD comment “the current UMD passes NULL” is false; <code>c88154be</code>'s “1 s bounded fallback” is 10 s in code</td>
        <td class="v y">Right</td>
        <td>Both carried into the handoff document unchallenged</td></tr>
    </tbody>
    <tfoot><tr><td>Ten claims</td><td class="n">6 ✓ · 2 ◐ · 2 ✗</td><td></td></tr></tfoot>
  </table>
  </div>
</div>

<h3>Was Kimi efficient with those 71.4 M tokens?</h3>

<p class="lede-prose">Structurally, yes — it was the <em>leanest</em> of the three per unit of work attempted. Behaviourally, no — a large share of the budget went into recovering from its own malformed tool calls and into thinking rather than acting.</p>

<div class="rpt">
<div class="tiles">
    <div class="tile k"><div class="tl">Avg context / response</div><div class="tv">260 K</div><div class="ts">Fable 313 K · Opus 316 K</div></div>
    <div class="tile k"><div class="tl">Billed tokens / tool call</div><div class="tv">237 K</div><div class="ts">Fable 307 K · Opus 310 K</div></div>
    <div class="tile"><div class="tl">Output / response</div><div class="tv">596</div><div class="ts">Fable 1,002 · Opus 1,595</div></div>
    <div class="tile"><div class="tl">Thinking share of output</div><div class="tv">≈⅔</div><div class="ts">417 K chars / 175 blocks, est.</div></div>
    <div class="tile"><div class="tl">User-visible prose</div><div class="tv">7 K</div><div class="ts">chars, in 3h13m. Fable 61 K</div></div>
    <div class="tile"><div class="tl">Cache writes</div><div class="tv">0</div><div class="ts">endpoint reports all reuse as reads</div></div>
  </div>
</div>

<h4>Tool-call failure rate</h4>

<p class="lede-prose">Every failed tool call costs a full context replay to recover from. Kimi’s rate was roughly double Fable’s and an order of magnitude above Opus’s at the same point in their sessions. “Soft failures” include exit code 1, <code>String to replace not found</code>, <code>Build FAILED</code> and empty-result greps.</p>

<div class="rpt">
<div class="card">
    <ul class="bars">
      <li><span class="nm">Kimi — hard errors</span><span class="tr"><span class="fl k" style="width:66.7%"></span></span><span class="vv">8.0%</span></li>
      <li><span class="nm">Kimi — incl. soft</span><span class="tr"><span class="fl k" style="width:100%;opacity:.45"></span></span><span class="vv">12.0%</span></li>
      <li><span class="nm">Fable — hard errors</span><span class="tr"><span class="fl f" style="width:35.8%"></span></span><span class="vv">4.3%</span></li>
      <li><span class="nm">Fable — incl. soft</span><span class="tr"><span class="fl f" style="width:57.5%;opacity:.45"></span></span><span class="vv">6.9%</span></li>
      <li><span class="nm">Opus — hard errors</span><span class="tr"><span class="fl o" style="width:7.5%"></span></span><span class="vv">0.9%</span></li>
      <li><span class="nm">Opus — incl. soft</span><span class="tr"><span class="fl o" style="width:90.0%;opacity:.45"></span></span><span class="vv">10.8%</span></li>
    </ul>
    <div class="legend"><span class="lg">Measured over each session’s first 71.4 M tokens.
      Hard-error rate per tool: Kimi <b>Bash 10.3%</b> / <b>Edit 13.6%</b>;
      Fable <b>Bash 5.6%</b> / <b>Edit 0%</b>; Opus <b>Bash 0.5%</b> / <b>Edit 5.0%</b>.
      Opus’s comparatively high soft rate is mostly deliberate probing — greps and
      <code>findstr</code> queries that legitimately return nothing.</span></div>
  </div>
</div>

<h4>Where the 3h13m actually went</h4>

<div class="rpt">
<div class="card">
    <div class="strip">
      <div class="row">
        <div class="ph" style="width:54%;background:var(--m3)">audit + measurement · 1 h 45 m</div>
        <div class="ph" style="width:39%;background:var(--m4)">per-device attempt → bugcheck · 1 h 13 m</div>
        <div class="ph" style="width:7%;background:var(--m0)">redesign</div>
      </div>
      <div class="ticks"><span>11:58</span><span>13:43</span><span>14:57</span><span>15:11 ⏹</span></div>
    </div>
    <div class="note" style="margin-top:18px">
      <p>Inside those blocks, four concrete friction episodes ate roughly 40 minutes — about a
      fifth of the whole session — and the user eventually asked about it directly:</p>
      <ol>
        <li><b>CRLF versus <code>Edit</code> anchors — ~16 min.</b> Kimi tried to edit
        <code>viogpum.h</code> from a reconstructed anchor string; the file is CRLF, so the exact
        match failed. It wrote an anchor-asserting Python script, that anchor didn’t match either,
        and it ended up inspecting the bytes with <code>file</code>, <code>cat -A</code> and
        <code>repr()</code>. Its own thinking later names the cause exactly: <em>“my anchors keep
        being wrong because I’m reconstructing file contents from memory/diffs.”</em></li>
        <li><b>Fetching one WDK header — 10 turns, ~8 min.</b> Looking for
        <code>d3dkmddi.h</code> on the Windows dev box: wrong include subdirectory
        (<code>km/</code> instead of <code>shared/</code>), then five different shell quotings of
        the same <code>scp</code>, before giving up and <code>copy</code>-ing it to the home
        directory first.</li>
        <li><b>Eleven consecutive greps</b> chasing <code>SetEventOnCompletion</code> through
        virglrenderer, most returning nothing, each one a full context replay.</li>
        <li><b>Seven turns to launch a sampler</b> — discovering that <code>start /min</code>
        doesn’t detach over SSH, then that <code>nept.py test</code> blocks.</li>
        <li><b>The user eventually asked about it directly — and Kimi took the point.</b> At 15:03,
        mid-turn, the user typed: <em>“Why do you keep fighting with tools calls? Why not just scp
        the files locally and then scp it back?”</em> Two minutes later Kimi’s thinking answers it:
        <em>“That’s… exactly what I’m doing? The friction was (1) CRLF line endings breaking
        exact-string Edit matches, (2) my guessed anchor text not matching the actual file… Better:
        read the actual local file first, then edit with exact text.”</em> It changed method and the
        edits stopped failing. That is a mid-turn steer absorbed correctly without a restart — the
        one piece of technical direction it got, and it landed.</li>
      </ol>
      <p>Two failures were not Kimi’s fault and should be discounted from any judgement of the
      model:</p>
      <ul>
        <li><b>13 minutes dead to a protocol incompatibility.</b> Between 14:16 and 14:29 the
        endpoint returned <code>400 Invalid request: the message at position 512 with role
        'assistant' must not be empty</code> five times. The transcript shows the user cycling
        <code>/exit</code> → <code>continue</code> five times to get past it. Six of the nine
        “continue” prompts in this session are that recovery loop, not the model stalling.</li>
        <li><b>The budget ended the session mid-edit.</b> First
        <code>429 · account suspended due to insufficient balance</code> at 14:44, terminal at
        15:14. Kimi’s last action was an <code>Edit</code> at 15:11:11 fixing a
        <code>C2065</code> forward-reference it had just correctly diagnosed. It never got to
        compile, let alone test, its own redesign.</li>
      </ul>
    </div>
  </div>
</div>

<div class="rpt callout-only">
<div class="callout">
    <b>Efficiency verdict.</b> Per round trip Kimi was cheap — smallest context, fewest tokens per
    tool call. What it lacked was <em>yield</em>: 596 output tokens per response of which roughly
    two-thirds was internal reasoning, 7 K characters of prose to the user in three hours, and a
    tool-failure rate that turned a meaningful slice of the budget into recovery. It was not
    profligate; it was slow to convert tokens into verified state.
  </div>
</div>

This was my subjective experience as well. Kimi K3 spent most of its tokens fighting the tooling but when it got past the hurdle, the analysis it made felt smarter than Opus 4.8.

<h3>Fable 5 on the same prompt, at fractions of the same budget</h3>

<p class="lede-prose">The interesting numbers aren’t at the iso-token line — they’re well before it.</p>

<div class="rpt wide">
<div class="scroll">
  <table class="dt">
    <thead><tr><th>Milestone</th><th class="n">Wall clock</th><th class="n">Responses</th><th class="n">Billed</th><th class="n">% of Kimi’s budget</th><th class="n">List cost</th></tr></thead>
    <tbody>
      <tr><th>Full audit delivered — two root causes, both proven live with its own instrumentation, MSDN contract points verified, diagnostics patch + README written, memory updated</th>
        <td class="n">46 min</td><td class="n">78</td><td class="n">14.4 M</td><td class="n"><b>20%</b></td><td class="n">$22</td></tr>
      <tr><th>Both fixes implemented, built, committed, and validated — GT1 ×3 at 47.2/46.2/48.7 fps, tear test 0/20, overlap ≈1.0, <code>timeouts=0</code>. Then it stopped and idled for five hours.</th>
        <td class="n">1 h 57 m</td><td class="n">197</td><td class="n">57.1 M</td><td class="n"><b>80%</b></td><td class="n">$73</td></tr>
      <tr class="hi"><th>Iso-token line — by now three hours deep into a <em>second</em> problem (fullscreen scanout going headless) with the user watching the screen</th>
        <td class="n">7 h 20 m</td><td class="n">228</td><td class="n">71.5 M</td><td class="n">100%</td><td class="n">$94</td></tr>
      <tr><th>Session end — UMD run-ahead pacing, QEMU cocoa layer fixes, virglrenderer fence publication, an ETW investigation that falsified its own theory, a full Fire Strike matrix on both backends, and a history rewrite</th>
        <td class="n">17 h 54 m</td><td class="n">611</td><td class="n">322.0 M</td><td class="n">451%</td><td class="n">$392</td></tr>
    </tbody>
  </table>
  </div>
</div>

<div class="rpt callout-only">
<div class="callout">
    Fable reached a complete, live-verified, two-root-cause audit on <b>20% of Kimi’s token
    budget</b>, and a committed, benchmark-validated fix on <b>80%</b>. Then it went idle for five
    hours because it had finished what it was asked to do — which is itself a signal worth noting
    next to Kimi’s nine “continue” prompts.
  </div>
</div>

<h4>The fairness ledger</h4>

<p class="lede-prose">Four things separate these two runs besides the model. Two favour Fable heavily.</p>

<div class="rpt">
<div class="card note">
    <ul>
      <li><b>Fable started with Kimi’s conclusion in its context.</b> This is the big one. Claude
      Code auto-loads <code>MEMORY.md</code> at session start, and the top line at 00:20 on Jul 23
      read: <em>“Present-gate token association — <b>FIXED</b> — black frames = per-process token
      table exhausted after 16 pids → <code>tok=0</code> UN-GATED flips; <b>fix = adapter-global
      monotonic token</b>. 2 DEAD ENDS: per-device stamp = bugcheck 0xFC, contiguous retire =
      permanent wedge.”</em> That line is Kimi’s + Opus’s output from the previous night, and
      Fable’s first fix is precisely the design it names. In Fable’s favour: it re-derived the
      mechanism from code and proved it live with its own instrumentation, and only opened the full
      memory file at 01:04 — <em>after</em> that live proof, at which point it corrected the note
      from “FIXED” to “BROKEN AT HEAD”. But it was not searching a blank space.</li>
      <li><b>Kimi inherited a dirty tree; Fable a clean one.</b> Kimi opened on HEAD plus 736
      uncommitted lines of a previous agent’s in-progress work, and spent real effort establishing
      that the working diff matched the saved <code>UNSPLIT</code> patch. Opus split and committed
      that work overnight at the user’s request, so Fable opened on a clean tree at the same two
      commits.</li>
      <li><b>Kimi lost 7% of its span to a client/API incompatibility</b> unrelated to reasoning
      quality, and was killed mid-edit by the balance cap.</li>
      <li><b>Fable found something no one had handed it.</b> The FlipThread vsync-starvation bug
      appears in no handoff, no memory file, and no prior session. Fable found it in its first 46
      minutes by adding its own vsync counters, and its fix (periodic <code>KTIMER</code> +
      <code>KeWaitForMultipleObjects</code>) survives in the tree today. Kimi had the same counters
      available and never looked at vsync cadence — that gap is not explained by the head start.</li>
    </ul>
    <p style="margin-bottom:0">Both ran at effort <code>max</code> with a 1 M context window. Kimi
    ran through an Anthropic-compatible third-party endpoint with tool search disabled; its context
    peaked around 404 K, Fable’s around 997 K before compaction.</p>
  </div>
</div>

<h3>The day before: Opus 4.8, and what “a lot of hand-holding” cost</h3>

<p class="lede-prose">This is the session that produced the ground both later runs stood on — and it is also the least autonomous of the three by a wide margin. 22.9 hours, 533 M tokens, 1,128 responses, 92 separate human or harness interventions, five gate architectures abandoned and three further theories refuted.</p>

<h4>Composition of interventions</h4>

<div class="rpt">
<div class="card">
    <div class="stk"><span class="nm">Opus 4.8</span>
      <span class="tr">
        <span class="seg" style="width:59.8%;background:var(--m1)"></span>
        <span class="seg" style="width:2.2%;background:var(--m5)"></span>
        <span class="seg" style="width:18.5%;background:var(--m2)"></span>
        <span class="seg" style="width:17.4%;background:var(--m4)"></span>
        <span class="seg" style="width:2.2%;background:var(--m0)"></span>
      </span><span class="vv">92</span></div>
    <div class="stk"><span class="nm">Fable 5</span>
      <span class="tr" style="width:37.0%">
        <span class="seg" style="width:76.5%;background:var(--m1)"></span>
        <span class="seg" style="width:2.9%;background:var(--m5)"></span>
        <span class="seg" style="width:17.6%;background:var(--m2)"></span>
        <span class="seg" style="width:2.9%;background:var(--m0)"></span>
      </span><span class="vv">34</span></div>
    <div class="stk"><span class="nm">Kimi K3</span>
      <span class="tr" style="width:20.7%">
        <span class="seg" style="width:26.3%;background:var(--m1)"></span>
        <span class="seg" style="width:52.6%;background:var(--m5)"></span>
        <span class="seg" style="width:21.1%;background:var(--m2)"></span>
      </span><span class="vv">19</span></div>
    <div class="legend">
      <span class="lg"><i class="sw m1"></i>substantive human input</span>
      <span class="lg"><i class="sw m5"></i>bare nudge (“continue”, “go ahead”)</span>
      <span class="lg"><i class="sw m2"></i>interrupts</span>
      <span class="lg"><i class="sw m4"></i>Stop-hook / <code>/goal</code> enforcement</span>
      <span class="lg"><i class="sw m0"></i>auto-compaction</span>
    </div>
    <div class="note" style="margin-top:16px">
      <p>The raw <em>rate</em> is nearly identical across all three — 6.6, 6.0 and 6.6 interventions
      per active hour for Opus, Fable and Kimi. What differs completely is the <em>kind</em>:</p>
      <ul>
        <li><b>Opus — 92, of which 55 substantive.</b> Roughly <b>19 were corrections of a wrong
        claim or a wrong path</b>, on top of 17 interrupts and 16 Stop-hook messages generated by two
        <code>/goal</code> conditions the user set specifically to stop it giving up and reverting.
        Median unattended run: <b>8 responses</b>. Eleven of the 55 were typed mid-turn and appear
        only in the queue records.</li>
        <li><b>Fable — 34, of which 26 substantive.</b> About 9 were human eyes-on-screen reports
        the model genuinely could not obtain itself, 6 were git hygiene requests, and 6 were design
        challenges — every one of which produced a real result. One bare nudge in eighteen hours.
        Median unattended run: <b>15 responses</b>; longest, 118 over 63 minutes.</li>
        <li><b>Kimi — 19, of which only 5 substantive:</b> the opening prompt, a progress-report
        request, a debugging hint (<em>“check kdnet, the kmd likely crashed”</em>), the mid-turn
        workflow question, and the closing cleanup request. <b>Ten of the nineteen are bare
        nudges</b> — nine <code>continue</code> and one <code>/compact</code>, and six of those
        nine are the recovery loop for the API-400 fault rather than the model stalling. So: two
        pieces of technical direction in three hours. Median unattended run: <b>18 responses</b>;
        it ran 156 responses over 104 minutes before the first human word.</li>
      </ul>
    </div>
  </div>
</div>

<h3>Autonomy, measured three ways</h3>

<p class="lede-prose">“Can it operate autonomously” resolves into three separable questions: how long does it run unattended, how often does it need <em>correcting</em> as opposed to <em>informing</em>, and does it self-arrest when it has finished.</p>

<div class="rpt">
<div class="card">
    <ul class="bars">
      <li><span class="nm">Median unattended run</span><span class="tr"><span class="fl k" style="width:100%"></span></span><span class="vv">Kimi 18</span></li>
      <li><span class="nm"></span><span class="tr"><span class="fl f" style="width:83.3%"></span></span><span class="vv">Fable 15</span></li>
      <li><span class="nm"></span><span class="tr"><span class="fl o" style="width:44.4%"></span></span><span class="vv">Opus 8</span></li>
    </ul>
    <div class="legend"><span class="lg">API responses between consecutive human inputs, queued
      messages included. Longest single run: Kimi <b>156</b> (104 min) · Fable <b>118</b> (63 min) ·
      Opus <b>220</b> (180 min).</span></div>
    <ul class="bars" style="margin-top:14px;border-top:1px solid var(--hair);padding-top:10px">
      <li><span class="nm">Corrective inputs / active hour</span><span class="tr"><span class="fl o" style="width:100%"></span></span><span class="vv">Opus 3.7</span></li>
      <li><span class="nm"></span><span class="tr"><span class="fl f" style="width:28.4%"></span></span><span class="vv">Fable 1.05</span></li>
      <li><span class="nm"></span><span class="tr"><span class="fl k" style="width:18.6%"></span></span><span class="vv">Kimi 0.69</span></li>
    </ul>
    <div class="legend"><span class="lg">Corrections, interrupts and Stop-hook enforcement only —
      excluding bare nudges and human eyes-on-screen reports the model could not obtain itself.
      This is the metric that separates the three; total intervention <em>rate</em> does not.</span></div>
  </div>
</div>

<div class="rpt callout-only">
<div class="callout">
    On the narrow question — <em>does it go down wrong paths or zone in on the
    solution?</em>: <b>Kimi took the fewest
    wrong turns per unit of work and needed almost no steering</b>; it simply converted tokens into
    verified state slowly, and ran out. <b>Opus took the most wrong turns by a large margin</b> and
    needed a human to catch three of them — but it was also the only session doing genuinely
    open-ended search, with no handoff describing the answer. <b>Fable is the one that both zoned in
    and finished</b>, which is exactly what you’d expect from the run that inherited two days of
    someone else’s conclusions.
  </div>
</div>

<h3>Verdicts</h3>

<div class="rpt wide">
<div class="verdict">
    <div class="card k">
      <h4>Kimi K3</h4>
      <p class="tagline">Right direction · slow conversion · killed early</p>
      <p><b>Direction: yes.</b> It identified the correct root-cause class within 105 minutes,
      found the real defect in the incumbent fix, eliminated one candidate design with a kernel
      crash dump, and proposed the next one — which was good enough that both Opus and Fable
      adopted it before Fable found the flaw. Six of its ten substantive claims survive
      unchallenged.</p>
      <p><b>Efficiency: mixed.</b> Leanest context and cheapest per tool call of the three, but the
      lowest yield per token — two-thirds of its output was internal reasoning, its tool-failure
      rate was 8.0% against Fable’s 4.3%, and roughly a fifth of its wall clock went to environment
      friction it partly created (CRLF anchors, header hunting, repeated failed greps). When the
      user pointed that out mid-turn it diagnosed the cause correctly and changed method.</p>
      <p><b>The real miss</b> isn’t the superseded design — it’s declaring the multi-second frozen
      frame benign. That was failure mode 2 in the prompt, it had two genuine driver causes, and
      Fable found the first one in 46 minutes using instrumentation Kimi had already built.</p>
    </div>
    <div class="card f">
      <h4>Fable 5</h4>
      <p class="tagline">Zoned in · finished · inherited a head start</p>
      <p>Delivered a complete two-root-cause audit on 20% of Kimi’s budget and a committed,
      GT1-validated fix on 80%. Then stopped, having done what it was asked. Over the following
      15 hours it fixed the scanout path, falsified its own disk-burst theory with a guest ETW trace
      and said so plainly, ran a controlled experiment on a UMD threading cap and rejected it,
      reverted a design it had shipped hours earlier once it proved it wrong, and rewrote history
      to remove it — verifying the final tree bit-identical to the benchmarked one.</p>
      <p><b>Caveat that matters:</b> its opening context contained Kimi’s and Opus’s conclusion in
      one line, including the fix design and both dead ends. The iso-token comparison is not a
      cold-start comparison. Its independent contribution is the vsync-starvation find, the
      per-thread association, the flip queue, and the UMD pacing — none of which was handed to it.</p>
    </div>
    <div class="card o">
      <h4>Opus 4.8</h4>
      <p class="tagline">Hardest problem · most steering · foundational output</p>
      <p>The only session doing open-ended search with no handoff describing the answer, and the
      one that paid for it: eight abandoned architectures, three claims retracted only after the
      user challenged them, 17 interrupts, and two <code>/goal</code> Stop-hook conditions written
      specifically to stop it giving up and reverting.</p>
      <p>It also found the bug that explained why every gate design had failed — the recycled
      manual-reset proxy fd — and shipped four commits across four repos plus the entire
      measurement apparatus the other two sessions used. Its 21-minute rescue of Kimi’s broken tree
      is the sharpest work in the whole dataset: diagnose a bugcheck, fix it, refuse a passing
      measurement, prove the underlying design unsound, replace it, re-measure, hand off.</p>
      <p>The honest reading is that heavy hand-holding was <em>working</em>: every correction
      landed and moved the investigation forward. It just needed a lot of them.</p>
    </div>
  </div>
</div>
