---
title: "Introducing Triton: DirectX 11 driver for QEMU"
subtitle: "You can now play modern Windows games in QEMU"
date: 2026-07-24
human: osy
ai: claude-opus-4-8
tags: [qemu,neptune,triton,graphics,windows]
---

[In the prequel]({% post_url 2026-05-16-introducing-neptune-direct3d-virtualization-for-qemu %}), we introduced Neptune, a Direct3D protocol forwarding layer for VirtIO. Neptune allowed us to serialize Direct3D API calls across the hypervisor boundary and this allowed us to run Wine games on a Linux guest with a Linux host faster than with DXVK directly in the guest. Admittedly, the payoff there was not that exciting but it laid the groundwork for our real goal: modern graphics acceleration for Windows guests. We have now achieved this by building a brand new Windows driver called Triton which along with Neptune brings full DirectX 11 support to QEMU virtual machines.

[![Screenshot of game running on QEMU on macOS host](/assets/images/posts/triton/windows-crash-bandicoot.png)](/assets/images/posts/triton/windows-crash-bandicoot.png){:target="_blank"}
*Crash Bandicoot Trilogy (x64) running on Windows 11 ARM64 virtualized on macOS through QEMU*

# What is Triton?

You might be wondering: if Neptune can serialize Direct3D API calls and Windows uses Direct3D, then aren't we already done? If Direct3D works in Wine, it should also work in Windows, right? After all, what is Wine, if not a [Windows emulator](https://www.winehq.org/about)? The short answer is: you sort of can. The Neptune Mesa drivers build a `d3d11.dll` and `dxgi.dll` which fully implements the Direct3D API set and so if you just put those files next to the game's executable, it should load them instead of Windows' own drivers and you can get some games to run that way. This is also the approach done by [previous attempts](https://github.com/arehnman/kvm-guest-drivers-windows) which used DXVK→Vulkan→Venus to run Direct3D locally inside an application. There are a few disadvantages to this approach. First and most importantly, you cannot get good performance because the window compositor (DWM) "sees" your frame as an image so it needs to use CPU blitting to copy the GPU image buffer to the correct window location. You might be able to do some tricks for full-screen applications to scanout natively but you will never get a smooth desktop experience. Second, because `d3d11.dll` and `dxgi.dll` are core components of Windows, you cannot replace the system files themselves and expect Windows to still work. Even if you do manage to get it to work, you will not be able to play many games with anti-cheats which specifically detect this kind of modification. That is why it is only possible to get the DLL to load on a per-application basis (and compatibility varies). Which brings us to the last point: needing to copy files to every application you want working graphics acceleration is not a user friendly experience. The correct approach is not to implement the DirectX APIs but to implement the DirectX DDIs (Device Driver Interface).

<aside class="aside author-human">
If you want a full play by play of the entire development process, check out <a href="{% post_url 2026-07-24-bringup-notes-building-triton %}">this companion post</a>.
</aside>

## DDI

<div class="chart-frame">
  <svg viewBox="0 0 720 560" width="100%" height="560" preserveAspectRatio="xMidYMid meet" font-family="-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, 'Helvetica Neue', Arial, sans-serif" role="img" aria-label="The DirectX 11 driver stack: Application, Direct3D 11, User-mode driver, and DXGI in user mode; Kernel-mode driver and Hardware / Virtualization in kernel mode.">
    <defs>
      <marker id="dxgi-arrow" markerWidth="8" markerHeight="8" refX="5.5" refY="3" orient="auto-start-reverse">
        <polygon points="0 0, 6 3, 0 6" style="fill:var(--text-faint)"/>
      </marker>
      <filter id="dxgi-shadow" x="-20%" y="-50%" width="140%" height="200%">
        <feDropShadow dx="0" dy="1" stdDeviation="1.5" flood-color="#0b1020" flood-opacity="0.07"/>
      </filter>
    </defs>

    <!-- User mode region -->
    <rect x="40" y="20" width="640" height="312" rx="16" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5"/>
    <text x="60" y="48" style="fill:var(--text-faint)" font-size="13" font-weight="600">User mode</text>

    <rect x="90" y="64" width="540" height="46" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#dxgi-shadow)"/>
    <text x="360" y="92" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="500">Application</text>

    <rect x="90" y="132" width="540" height="46" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#dxgi-shadow)"/>
    <text x="360" y="160" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="500">Direct3D 11 (d3d11.dll)</text>

    <rect x="90" y="200" width="540" height="46" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#dxgi-shadow)"/>
    <text x="360" y="228" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="500">User-mode driver (DDI)</text>

    <rect x="90" y="268" width="540" height="46" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#dxgi-shadow)"/>
    <text x="360" y="296" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="500">DXGI (dxgi.dll)</text>

    <!-- Kernel mode region -->
    <rect x="40" y="364" width="640" height="176" rx="16" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5"/>
    <text x="60" y="392" style="fill:var(--text-faint)" font-size="13" font-weight="600">Kernel mode</text>

    <rect x="90" y="408" width="540" height="46" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#dxgi-shadow)"/>
    <text x="360" y="436" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="500">Kernel-mode driver</text>

    <rect x="90" y="476" width="540" height="46" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#dxgi-shadow)"/>
    <text x="360" y="504" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="500">Hardware / Virtualization</text>

    <!-- flow arrows -->
    <path d="M 360 110 L 360 130" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#dxgi-arrow)"/>
    <path d="M 360 178 L 360 198" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#dxgi-arrow)"/>
    <path d="M 360 246 L 360 266" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#dxgi-arrow)"/>
    <path d="M 360 314 L 360 406" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#dxgi-arrow)"/>
    <path d="M 360 454 L 360 474" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#dxgi-arrow)"/>
    <!-- Application talks to DXGI directly -->
    <path d="M 630 87 H 648 Q 656 87 656 95 V 283 Q 656 291 648 291 H 634" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#dxgi-arrow)"/>
  </svg>
</div>

In Windows, the application communicates with the system Direct3D and DXGI libraries. The `d3d11.dll` (as well as older versions) do the complicated work of state tracking and send a more sanitized stream of commands to the user-mode driver (UMD) which implements the DDI. The application also talks to `dxgi.dll` to initialize the graphics adapters, set up the swapchain, etc. The UMD also goes through the DXGI to talk with the kernel-mode driver (KMD). The KMD is implemented by the graphics vendor (us) to drive the actual hardware (or in our case the virtual hardware). For Wine, we implemented a custom `d3d11.dll` and `dxgi.dll` to intercept the API calls and now for Windows, we need to instead implement the UMD and KMD.

So that's the challenge: implement the UMD with the DirectX DDI interface and also set up a private interface with the KMD which communicates with the VirtIO device.

Lucky for us, the second part has already been solved. Both [anonymix007](https://github.com/anonymix007/kvm-guest-drivers-windows-venus/tree/viogpu3d-venus) and [arehnman](https://github.com/arehnman/kvm-guest-drivers-windows) had independently been working on a KMD for Venus (Vulkan). Since Vulkan is a completely independent graphics API, it does not need to implement the DirectX DDI and its UMD is similar to the "replace `d3d11.dll`" approach in that it talks directly with the KMD to drive commands to QEMU. Since Neptune is modelled after Venus, the high level kernel interfaces (for DMA, command buffers, etc) is very similar and the interface between UMD and KMD is exactly the same. Ultimately, we chose to use anonymix007's branch as the base because their implementation [had more features working on the KMD side](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/38731#note_3389999).

That leaves us with the hard part. We have to implement the DDI for DirectX 11. When you are designing a new system, it is always wise to understand how others who have come before have solved similar problems. Unfortunately, there are not many open source DDI implementations to draw inspiration from. Windows graphics drivers is a very niche subject and most of the experts work in one of the handful of graphics hardware vendors. This is one of the reasons that QEMU has never got far with Windows GPU acceleration.

Fortunately for us, there are two working open source implementation that we can learn from. First, Mesa has a [DirectX 10 UMD](https://gitlab.freedesktop.org/mesa/mesa/-/tree/main/src/gallium/frontends/d3d10umd?ref_type=heads). If you did not read [the last article]({% post_url 2026-05-16-introducing-neptune-direct3d-virtualization-for-qemu %}#gallium-for-windows), the short version is that Mesa implements OpenGL for Linux. Mesa performs state tracking for OpenGL and emits Gallium API calls. The Mesa DirectX 10 UMD is an alternative to OpenGL that emits the same Gallium API calls. Then the Gallium backend driver (AMD, Intel, VirGL, etc) converts them into native graphics driver APIs. The upstream Mesa only supports the software rasterization backend for DirectX 10 but there was some recent work to get it working with VirGL. Unfortunately, the macOS virglrenderer lacks support for many of the features that this UMD requires so it is not a viable way to get graphics acceleration for macOS hosts. However, the integration with the Mesa codebase provides us with a clean example for integrating Triton.

VirtualBox has the only [working open source DirectX 11 UMD](https://github.com/VirtualBox/virtualbox/tree/main/src/VBox/Additions/win/Graphics/Video/disp/wddm). However, this driver cannot really be "adopted" for our use. The way their driver works is that they translate the DDI calls into an intermediate bytecode and then on the host side, they interpret the bytecode into DirectX API calls. While it would be easy (with AI help) to just port this bytecode emitter and interpreter into QEMU, we decided against it for a couple of reasons. First, we think this conversion of DDI into a bytecode and then lifting that bytecode back to DirectX API can result in bugs that limit compatibility with games. Indeed, reading forum threads online, it seems like many games do not run in VirtualBox for this reason. If there is a missing feature or bug in the translation engine, it would require a lot of active maintenance effort to fix and we do not want to depend on Oracle for that. Second, there is a licence incompatibility between VirtualBox's GPLv3 and virglrenderer's MIT License or QEMU's LGPLv2. VirtualBox's code can't be integrated but we did learn some valuable insight from it. Their list of which DDI prototypes were implemented and which ones returned error is used as the minimal requirements for a working implementation. This information isn't readily available from MSDN documentation and trying to implement every single prototype would be massive in scope. Their DXBC signature algorithm is also helpful to understand because Microsoft does not publish it anywhere.

Since we didn't want to take the VirtualBox approach of using an intermediate transport format for DDI calls, we can do something better. If you imagine `d3d11.dll` as a component that roughly transforms DirectX API calls into UMD DDI calls, then what we want our UMD to do is to transform the DDI call back to DirectX API calls. Why is this useful? Because then we can use our tested and working Neptune protocol without having to invent a new transport for serializing DDI calls. On the host side, we do not have to do any extra work to execute those calls. VirtualBox needs an emitter and transport layer on the guest as well as an interpreter and dispatcher on the host. Each step adds latency and the chance to introduce errors and incompatibility. We still need an emitter and transport on the guest but on the host side we do not need an interpreter because the deserialized Neptune commands ARE DirectX 11 API calls and can be dispatched without any additional parsing. One less transform step means less opportunity for mistakes. Another advantage of a DDI→API transform is that most DDI calls in D3D11 have an API equivalent meaning that the transform is as simple as mapping some API handles to device handles and sometimes doing a lookup for API→DDI enum differences. The biggest win however, also turns out to be the most complicated part of the story, which is the DXBC shader code.

## DXBC

DXBC (DirectX Byte Code) is the IR code that Microsoft's shader compiler (FXC) emits. Specifically, it is the older (pre-DirectX 12) format and is compiled from HLSL, the shader language that DirectX uses. Since Triton acts as a reverse transform from DDI to API, it does not need to disassemble and convert this shader bytecode. This is a huge win for us in terms of complexity and compatibility. Unfortunately, it is not as simple as passing the bytecode unmodified to the host.

<div class="chart-frame">
  <svg viewBox="0 0 760 700" width="100%" height="700" preserveAspectRatio="xMidYMid meet" font-family="-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, 'Helvetica Neue', Arial, sans-serif" role="img" aria-label="How a shader travels from HLSL to the driver: the application compiles HLSL with FXC into a DXContainer holding a header and parts (SHDR, ISGN, OSGN, and others). The whole container is passed to d3d11.dll via ID3D11Device::CreateVertexShader, but d3d11.dll forwards only the SHDR part to the Triton user-mode driver via pfnCreateVertexShader.">
    <defs>
      <marker id="shdr-arrow" markerWidth="8" markerHeight="8" refX="5.5" refY="3" orient="auto-start-reverse">
        <polygon points="0 0, 6 3, 0 6" style="fill:var(--text-faint)"/>
      </marker>
      <marker id="shdr-arrow-accent" markerWidth="8" markerHeight="8" refX="5.5" refY="3" orient="auto-start-reverse">
        <polygon points="0 0, 6 3, 0 6" style="fill:var(--accent)"/>
      </marker>
      <filter id="shdr-shadow" x="-20%" y="-50%" width="140%" height="200%">
        <feDropShadow dx="0" dy="1" stdDeviation="1.5" flood-color="#0b1020" flood-opacity="0.07"/>
      </filter>
    </defs>

    <!-- Application -->
    <rect x="230" y="24" width="300" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#shdr-shadow)"/>
    <text x="380" y="45" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="600">Application</text>
    <text x="380" y="63" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">authors HLSL shader source</text>

    <path d="M 380 76 L 380 106" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#shdr-arrow)"/>
    <text x="396" y="95" style="fill:var(--text-muted)" font-size="11">HLSL source</text>

    <!-- FXC -->
    <rect x="230" y="108" width="300" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#shdr-shadow)"/>
    <text x="380" y="129" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="600">FXC</text>
    <text x="380" y="147" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">HLSL &#8594; DXBC shader compiler</text>

    <path d="M 380 160 L 380 190" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#shdr-arrow)"/>
    <text x="396" y="179" style="fill:var(--text-muted)" font-size="11">emits</text>

    <!-- DXContainer -->
    <rect x="200" y="196" width="360" height="266" rx="12" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5"/>
    <text x="220" y="221" style="fill:var(--text)" font-size="14" font-weight="600">DXContainer</text>
    <text x="540" y="221" text-anchor="end" style="fill:var(--text-faint)" font-size="11">header + parts</text>

    <!-- part: Header -->
    <rect x="224" y="236" width="312" height="34" rx="7" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.25"/>
    <text x="240" y="258" style="fill:var(--text)" font-size="12.5" font-weight="600">Header</text>
    <text x="520" y="258" text-anchor="end" style="fill:var(--text-muted)" font-size="11">magic, version, part table</text>

    <!-- part: SHDR (the only one forwarded) -->
    <rect x="224" y="278" width="312" height="34" rx="7" style="fill:var(--accent-tint);stroke:var(--accent)" stroke-width="1.5"/>
    <text x="240" y="300" style="fill:var(--accent)" font-size="12.5" font-weight="700" font-family="ui-monospace, 'SF Mono', Menlo, Consolas, monospace">SHDR</text>
    <text x="520" y="300" text-anchor="end" style="fill:var(--text)" font-size="11" font-weight="500">DXBC bytecode</text>

    <!-- part: ISGN -->
    <rect x="224" y="320" width="312" height="34" rx="7" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.25"/>
    <text x="240" y="342" style="fill:var(--text)" font-size="12.5" font-weight="600" font-family="ui-monospace, 'SF Mono', Menlo, Consolas, monospace">ISGN</text>
    <text x="520" y="342" text-anchor="end" style="fill:var(--text-muted)" font-size="11">input signature (metadata)</text>

    <!-- part: OSGN -->
    <rect x="224" y="362" width="312" height="34" rx="7" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.25"/>
    <text x="240" y="384" style="fill:var(--text)" font-size="12.5" font-weight="600" font-family="ui-monospace, 'SF Mono', Menlo, Consolas, monospace">OSGN</text>
    <text x="520" y="384" text-anchor="end" style="fill:var(--text-muted)" font-size="11">output signature (metadata)</text>

    <!-- part: others -->
    <rect x="224" y="404" width="312" height="34" rx="7" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.25"/>
    <text x="240" y="426" style="fill:var(--text-muted)" font-size="12.5" font-weight="600">&#8230;</text>
    <text x="520" y="426" text-anchor="end" style="fill:var(--text-muted)" font-size="11">other metadata parts</text>

    <!-- whole container to d3d11.dll -->
    <path d="M 380 462 L 380 512" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#shdr-arrow)"/>
    <text x="396" y="484" style="fill:var(--text-muted)" font-size="11.5" font-family="ui-monospace, 'SF Mono', Menlo, Consolas, monospace">ID3D11Device::CreateVertexShader</text>
    <text x="396" y="500" style="fill:var(--text-muted)" font-size="11">passes the entire container</text>

    <!-- d3d11.dll -->
    <rect x="230" y="514" width="300" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#shdr-shadow)"/>
    <text x="380" y="535" text-anchor="middle" style="fill:var(--text)" font-size="15" font-weight="600" font-family="ui-monospace, 'SF Mono', Menlo, Consolas, monospace">d3d11.dll</text>
    <text x="380" y="553" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">Direct3D 11 runtime</text>

    <!-- only SHDR to the UMD -->
    <path d="M 380 566 L 380 618" style="fill:none;stroke:var(--accent)" stroke-width="2" marker-end="url(#shdr-arrow-accent)"/>
    <text x="396" y="588" style="fill:var(--text-muted)" font-size="11.5" font-family="ui-monospace, 'SF Mono', Menlo, Consolas, monospace">pfnCreateVertexShader</text>
    <text x="396" y="604" style="fill:var(--accent)" font-size="11" font-weight="600">passes the SHDR part only</text>

    <!-- UMD -->
    <rect x="230" y="620" width="300" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#shdr-shadow)"/>
    <text x="380" y="641" text-anchor="middle" style="fill:var(--text)" font-size="15.5" font-weight="600">UMD (Triton)</text>
    <text x="380" y="659" text-anchor="middle" style="fill:var(--text-muted)" font-size="11">user-mode driver</text>
  </svg>
</div>

The compiler (FXC) emits the DXBC bytecode along with other metadata. `d3d11.dll` expects to see this metadata and consumes it. When the DDI is called, only the bytecode is passed. That means for us to make a valid "inverse transform" back to the API call, we need to re-construct all that metadata by interpreting the bytecode. In the end we still pass through the bytecode unmodified but since we don't see the original DXContainer file, we have to synthesize fields that the host DirectX renderer expects. This was a lot of trial and error that the AI assistant handled but it is the weakest and most error prone part of our implementation.

# Host Renderer

Here's what we have so far:

<div class="chart-frame">
  <svg viewBox="0 0 760 690" width="100%" height="690" preserveAspectRatio="xMidYMid meet" font-family="-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, 'Helvetica Neue', Arial, sans-serif" role="img" aria-label="The eight-step path a frame takes from the guest application to the host renderer. Steps 1–6 run in the guest; steps 7–8 run on the host; the guest/host boundary sits between step 6 and step 7.">
    <defs>
      <marker id="flow-arrow" markerWidth="9" markerHeight="9" refX="5.5" refY="3" orient="auto">
        <polygon points="0 0, 6 3, 0 6" style="fill:var(--accent)"/>
      </marker>
      <filter id="flow-shadow" x="-20%" y="-60%" width="140%" height="220%">
        <feDropShadow dx="0" dy="1" stdDeviation="1.5" flood-color="#0b1020" flood-opacity="0.07"/>
      </filter>
    </defs>

    <!-- Guest lane -->
    <rect x="24" y="30" width="712" height="450" rx="16" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5"/>
    <text x="46" y="55" style="fill:var(--text-faint)" font-size="13" font-weight="700" letter-spacing="0.08em">GUEST</text>

    <!-- Host lane -->
    <rect x="24" y="500" width="712" height="162" rx="16" style="fill:var(--accent-tint);stroke:var(--border)" stroke-width="1.5"/>
    <text x="46" y="525" style="fill:var(--accent)" font-size="13" font-weight="700" letter-spacing="0.08em">HOST</text>
    <text x="716" y="493" text-anchor="end" style="fill:var(--text-faint)" font-size="11">guest &#8594; host boundary</text>

    <!-- Flow spine (threads through every node, crossing the boundary at 6-&gt;7) -->
    <path d="M 380 110 L 380 140" style="fill:none;stroke:var(--accent)" stroke-width="2.5" marker-end="url(#flow-arrow)"/>
    <path d="M 380 176 L 380 206" style="fill:none;stroke:var(--accent)" stroke-width="2.5" marker-end="url(#flow-arrow)"/>
    <path d="M 380 242 L 380 272" style="fill:none;stroke:var(--accent)" stroke-width="2.5" marker-end="url(#flow-arrow)"/>
    <path d="M 380 308 L 380 338" style="fill:none;stroke:var(--accent)" stroke-width="2.5" marker-end="url(#flow-arrow)"/>
    <path d="M 380 374 L 380 404" style="fill:none;stroke:var(--accent)" stroke-width="2.5" marker-end="url(#flow-arrow)"/>
    <path d="M 380 440 L 380 537" style="fill:none;stroke:var(--accent)" stroke-width="2.5" stroke-dasharray="6 5" marker-end="url(#flow-arrow)"/>
    <path d="M 380 573 L 380 607" style="fill:none;stroke:var(--accent)" stroke-width="2.5" marker-end="url(#flow-arrow)"/>

    <!-- Connector ticks -->
    <line x1="362" y1="92"  x2="346" y2="92"  style="stroke:var(--border)" stroke-width="1.5"/>
    <line x1="398" y1="158" x2="414" y2="158" style="stroke:var(--border)" stroke-width="1.5"/>
    <line x1="362" y1="224" x2="346" y2="224" style="stroke:var(--border)" stroke-width="1.5"/>
    <line x1="398" y1="290" x2="414" y2="290" style="stroke:var(--border)" stroke-width="1.5"/>
    <line x1="362" y1="356" x2="346" y2="356" style="stroke:var(--border)" stroke-width="1.5"/>
    <line x1="398" y1="422" x2="414" y2="422" style="stroke:var(--border)" stroke-width="1.5"/>
    <line x1="362" y1="555" x2="346" y2="555" style="stroke:var(--border)" stroke-width="1.5"/>
    <line x1="398" y1="625" x2="414" y2="625" style="stroke:var(--border)" stroke-width="1.5"/>

    <!-- Cards (alternating sides) -->
    <rect x="60"  y="66"  width="286" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#flow-shadow)"/>
    <text x="330" y="96" text-anchor="end" font-size="12.5"><tspan font-weight="700" style="fill:var(--text)">Application</tspan><tspan style="fill:var(--text-muted)"> &#183; DirectX / DXGI API calls</tspan></text>

    <rect x="414" y="132" width="286" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#flow-shadow)"/>
    <text x="430" y="162" font-size="12.5"><tspan font-weight="700" style="fill:var(--text)">System libraries</tspan><tspan style="fill:var(--text-muted)"> &#183; DDI calls into Triton</tspan></text>

    <rect x="60"  y="198" width="286" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#flow-shadow)"/>
    <text x="330" y="228" text-anchor="end" font-size="12.5"><tspan font-weight="700" style="fill:var(--text)">Triton</tspan><tspan style="fill:var(--text-muted)"> &#183; DXBC &#8594; DXContainer &#8594; Neptune</tspan></text>

    <rect x="414" y="264" width="286" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#flow-shadow)"/>
    <text x="430" y="294" font-size="12.5"><tspan font-weight="700" style="fill:var(--text)">Neptune UMD</tspan><tspan style="fill:var(--text-muted)"> &#183; serialize into the ring buffer</tspan></text>

    <rect x="60"  y="330" width="286" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#flow-shadow)"/>
    <text x="330" y="360" text-anchor="end" font-size="12.5"><tspan font-weight="700" style="fill:var(--text)">KMD</tspan><tspan style="fill:var(--text-muted)"> &#183; VirtIO commands to the host</tspan></text>

    <rect x="414" y="396" width="286" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#flow-shadow)"/>
    <text x="430" y="426" font-size="12.5"><tspan font-weight="700" style="fill:var(--text)">QEMU host</tspan><tspan style="fill:var(--text-muted)"> &#183; hands calls to virglrenderer</tspan></text>

    <rect x="60"  y="529" width="286" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#flow-shadow)"/>
    <text x="330" y="559" text-anchor="end" font-size="12.5"><tspan font-weight="700" style="fill:var(--text)">Neptune host</tspan><tspan style="fill:var(--text-muted)"> &#183; deserialize &#8594; host DirectX</tspan></text>

    <rect x="414" y="599" width="286" height="52" rx="10" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#flow-shadow)"/>
    <text x="430" y="629" font-size="12.5"><tspan font-weight="700" style="fill:var(--text)">Host DirectX</tspan><tspan style="fill:var(--text-muted)"> &#183; renders the frame</tspan></text>

    <!-- Numbered station badges (drawn last, on top of the spine) -->
    <circle cx="380" cy="92"  r="18" style="fill:var(--accent)"/><text x="380" y="97"  text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="700">1</text>
    <circle cx="380" cy="158" r="18" style="fill:var(--accent)"/><text x="380" y="163" text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="700">2</text>
    <circle cx="380" cy="224" r="18" style="fill:var(--accent)"/><text x="380" y="229" text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="700">3</text>
    <circle cx="380" cy="290" r="18" style="fill:var(--accent)"/><text x="380" y="295" text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="700">4</text>
    <circle cx="380" cy="356" r="18" style="fill:var(--accent)"/><text x="380" y="361" text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="700">5</text>
    <circle cx="380" cy="422" r="18" style="fill:var(--accent)"/><text x="380" y="427" text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="700">6</text>
    <circle cx="380" cy="555" r="18" style="fill:var(--accent)"/><text x="380" y="560" text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="700">7</text>
    <circle cx="380" cy="625" r="18" style="fill:var(--accent)"/><text x="380" y="630" text-anchor="middle" style="fill:var(--accent-on)" font-size="15" font-weight="700">8</text>
  </svg>
</div>

1. Application makes DirectX and DXGI API calls to the system libraries.
2. System libraries invoke Triton through DDI calls.
3. Triton DDI converts raw DXBC bytecode back into DXContainer and makes DirectX and DXGI API calls to Neptune.
4. Neptune UMD serializes the API calls and passes them through a ring buffer managed by the KMD.
5. KMD uses the VirtIO interface to send commands to the host.
6. QEMU host handles the command and passes Neptune calls to virglrenderer.
7. Neptune host module in virglrenderer deserializes the API calls and forwards them to the host side DirectX implementation.
8. Host DirectX implementation renders the frame.

Let's zoom in on the last point. Once the DirectX API calls make it to the host, we still need to render it. When we brought up Neptune for Wine on Linux, we [forked DXVK](https://github.com/osy/dxvk) to support exporting the swapchain images as DMAbuf resources. At the time, we decided to implement the swapchain on the host side in order to sidestep the issue of shared textures. Internally, swapchain images are represented as textures but these textures are special in that the host needs to be able to find them and use them to show the final frame on screen. Our Wine DXGI library forwards all the swapchain API calls directly to the host and therefore the host "knows" which textures will be used as a backbuffer. Then separate VirGL commands can be used to scan out the texture blob to the VM window. This trades simplicity in the guest driver and minimal changes in DXVK for the complexity of swapchain logic in the host virglrenderer process.

When bringing up Triton, we realized that host side swapchain handling was a mistake. On Windows, DXGI is a system component which talks to the UMD. DXGI handles the backbuffer creation, frame pacing, mode switching, etc. The UMD (mostly) doesn't give special treatment to DXGI and so our method of doing an "inverse transform" of DDI calls back to API calls does not really work with DXGI. That means all the swapchain logic we added to the host side is largely bypassed. The desktop compositor (DWM) operates on shared textures. One process's DXGI renders content to its own backbuffer and that backbuffer is shared with the DWM process which draws the desktop, window chrome, etc. The final frame that DWM constructs is set for scan out. This means that in addition to DMAbuf exports, we also need to implement DMAbuf imports in DXVK as well (separate guest contexts map to separate host contexts). Once we have both import and export implemented, there is no need for host side swapchain logic anymore and so to make the Wine driver more unified, we moved all the swapchain logic into the guest Neptune driver. An added benefit of this move is that it more closely tracks with how Venus is designed and so virglrenderer is kept clean.

[![Screenshot of Windows running on QEMU on Ubuntu host](/assets/images/posts/triton/ubuntu-windows-desktop.png)](/assets/images/posts/triton/ubuntu-windows-desktop.png){:target="_blank"}
*Windows DWM compositing working with DXVK shared textures on QEMU KVM running on Ubuntu*

## macOS

There's some challenge in getting virglrenderer working on macOS but since [Venus now runs in macOS](https://gitlab.freedesktop.org/virgl/virglrenderer/-/merge_requests/1602), most of the backend challenges have been fleshed out. The remaining task is to connect Neptune to a host side DirectX renderer. There are three major projects that can handle the goal of DirectX on macOS. However, they all been designed with running Wine as the main target. They lack the shared textures and shared fences features that Neptune and Triton requires.

### DXVK + MoltenVK

DXVK is the project we used on Linux hosts. It translates D3D11 API to Vulkan API and then uses the host Vulkan driver to do the rendering. On Linux, this works great because Vulkan is a first class citizen and all modern graphics hardware have a good Vulkan driver at this point. On macOS though, Vulkan is handled by another translation layer, MoltenVK, which translates Vulkan API to Metal API. [In the last post]({% post_url 2026-05-16-introducing-neptune-direct3d-virtualization-for-qemu %}#venus), we talked about the unique challenge of getting DXVK + MoltenVK working and the short version is: it is unstable and requires a lot more work for compatibility.

[![Crash Bandicoot running on patched MoltenVK + Venus](/assets/images/posts/neptune/macos-venus-dxvk.jpeg)](/assets/images/posts/neptune/macos-venus-dxvk.jpeg){:target="_blank"}
*Crash Bandicoot running on patched MoltenVK + Venus + DXVK (guest)*

### DXMT

DXMT sidesteps the Vulkan issue by translating D3D11 directly to Metal (with D3D12 coming soon). Just like DXVK, the project is designed primarily with Wine in mind so the first step was to [implement a native variant](https://github.com/utmapp/dxmt) of the library. With our fork, DXMT can be built as a macOS shared library and exposes some additional exports for import/export of textures and fences.

[![Screenshot of FireStrike result with DXMT backend](/assets/images/posts/triton/windows-firestrike-dxmt.png)](/assets/images/posts/triton/windows-firestrike-dxmt.png){:target="_blank"}
*FireStrike (x64) for Windows 11 ARM64 running on macOS host with DXMT backend*

#### Shared Textures

One major hurdle in the design of dxmt-native is in the implementation of shared textures that can cross the process boundary. We need to cross the process boundary because virglrenderer spawns helper processes for each renderer context so roughly every guest D3D context corresponds to a separate `virgl_render_server` process. This strict process isolation allows a renderer to crash without taking down the entire VM. Now, we can force the older thread based isolation model and use standard `MTLTexture` handles across renderer context boundary (and we will have to for the eventual iOS port), but [upstream maintainers](https://gitlab.freedesktop.org/virgl/virglrenderer/-/merge_requests/1582) do not want to support this. Sharing Metal resources across processes can be tricky but there are a few "well supported" way of doing it.

1. `MTLSharedTextureHandle` + XPC: This is the Apple preferred way but it requires bringing in XPC which is its own can of worms. Both QEMU and virglrenderer use file descriptors and `SCM_RIGHTS` to pass handles between processes but `MTLSharedTextureHandle` does not support this. For the best performance though, we should eventually adopt this across virglrenderer, QEMU, and SPICE but for this initial bringup, we want to not make major architectural changes across projects.
2. `IOSurface`: You can render to an IOSurface and share the global handle with any other process. This is how we implement the accelerated rendering on UTM but it is using technology long deprecated by Apple. You also need to pay the penalty of an additional GPU blit into the IOSurface and that also means having to set up a render pipeline in virglrenderer which adds complexity.
3. `CALayerHost`: A private API that is used by Chrome and other older macOS apps where rendering is done in a separate process. This is strictly worse than IOSurface in terms of latency (CoreAnimation is higher up the graphics stack) and the reverse (going from `CALayer` back to `MTLTexture`) is even more complicated. This technique may work for offline rendering but will not work for shared textures that must be composited.

None of these give us a good way to share textures across different processes using `SCM_RIGHTS` but a new idea was brought up (during the Venus discussion) by [@Drakulix](https://gitlab.freedesktop.org/virgl/virglrenderer/-/merge_requests/1582#note_3249210) (who was working on bringing Wayland to macOS). Their idea is to use `shm_open()` to create a shared memory object (which can be represented as a file descriptor that works across `SCM_RIGHTS`) and then map it to a `MTLBuffer` using `newBufferWithBytesNoCopy:length:options:deallocator:`. That gives us a single memory region that can be seen by the CPU and GPU and you can repeat this in the other process as well. All of this works in Apple Silicon because of UMA (Unified Memory Architecture) meaning that CPU and GPU share a single physical address space. The only downside is that you can only do this with linear textures which is not memory efficient. However, as long as the number of shared textures is small, this should not be an issue.

#### Shared Fences

Sharing textures between different contexts in different processes is one half of the equation. The other half is synchronization. When you have producer process A drawing to a shared texture and consumer process B compositing all the shared textures into the final scanout image, you will run into tearing if A is in middle of drawing when B starts compositing. To prevent this, you need fences which allows process A to block while B is drawing and B to block while A is drawing. To make matters more complicated, you need GPU fences because the GPU executes asynchronously to the CPU. Ideally, B's GPU process can consume A's GPU fence without any polling by A's CPU process. The only way to achieve this is to use `MTLSharedEventHandle` which requires XPC. However, we can get most of the way there with emulated fences by relying on two facts.

1. Most of our shared fence events happen at frame completion boundaries. That means the added latency of a CPU side wait is limited to one fence per completed frame.
2. The fence event producer can execute on the GPU while the fence consumer must wait on the CPU. That means we only need to waste CPU cycles on one side.

<div class="chart-frame">
  <svg viewBox="0 0 760 470" width="100%" height="470" preserveAspectRatio="xMidYMid meet" font-family="-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', system-ui, 'Helvetica Neue', Arial, sans-serif" role="img" aria-label="The emulated GPU fence across two processes. Producer process A and consumer process B each span a CPU and a GPU. The producer GPU writes a timeline value into shared memory after its draws complete; the consumer CPU spin-polls that value and only submits its composite work to the consumer GPU once the value appears, enforcing ordering.">
    <defs>
      <marker id="fence-arrow" markerWidth="8" markerHeight="8" refX="5.5" refY="3" orient="auto">
        <polygon points="0 0, 6 3, 0 6" style="fill:var(--text-faint)"/>
      </marker>
      <marker id="fence-arrow-accent" markerWidth="9" markerHeight="9" refX="5.5" refY="3" orient="auto">
        <polygon points="0 0, 6 3, 0 6" style="fill:var(--accent)"/>
      </marker>
      <filter id="fence-shadow" x="-20%" y="-50%" width="140%" height="200%">
        <feDropShadow dx="0" dy="1" stdDeviation="1.5" flood-color="#0b1020" flood-opacity="0.07"/>
      </filter>
    </defs>

    <!-- Row labels -->
    <text transform="rotate(-90 30 142)" x="30" y="142" text-anchor="middle" style="fill:var(--text-faint)" font-size="12" font-weight="700" letter-spacing="0.12em">CPU</text>
    <text transform="rotate(-90 30 317)" x="30" y="317" text-anchor="middle" style="fill:var(--text-faint)" font-size="12" font-weight="700" letter-spacing="0.12em">GPU</text>

    <!-- Process headers -->
    <text x="174" y="42" text-anchor="middle" style="fill:var(--text)" font-size="13.5" font-weight="600">Producer process (A)</text>
    <text x="586" y="42" text-anchor="middle" style="fill:var(--text)" font-size="13.5" font-weight="600">Consumer process (B)</text>

    <!-- Process boundaries (shared memory is mapped into both) -->
    <line x1="304" y1="60" x2="304" y2="404" style="stroke:var(--border)" stroke-width="1.5" stroke-dasharray="4 5"/>
    <line x1="456" y1="60" x2="456" y2="404" style="stroke:var(--border)" stroke-width="1.5" stroke-dasharray="4 5"/>

    <!-- Quadrant boxes -->
    <rect x="52"  y="88"  width="244" height="108" rx="12" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#fence-shadow)"/>
    <text x="174" y="112" text-anchor="middle" style="fill:var(--text)" font-size="14" font-weight="600">Producer CPU</text>
    <text x="174" y="138" text-anchor="middle" font-size="12"><tspan font-weight="700" style="fill:var(--accent)">1</tspan><tspan style="fill:var(--text)"> &#183; submit draws + fence write</tspan></text>
    <text x="174" y="160" text-anchor="middle" style="fill:var(--text-muted)" font-size="9.5" font-family="ui-monospace, 'SF Mono', Menlo, Consolas, monospace">ClearUnorderedAccessViewUint</text>

    <rect x="464" y="88"  width="244" height="108" rx="12" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#fence-shadow)"/>
    <text x="586" y="110" text-anchor="middle" style="fill:var(--text)" font-size="14" font-weight="600">Consumer CPU</text>
    <text x="586" y="134" text-anchor="middle" font-size="12"><tspan font-weight="700" style="fill:var(--accent)">4</tspan><tspan style="fill:var(--text)"> &#183; spin-poll shared memory</tspan></text>
    <text x="586" y="152" text-anchor="middle" style="fill:var(--text-muted)" font-size="9.5">on the CPU &#8212; no GPU poll on Apple</text>
    <text x="586" y="178" text-anchor="middle" font-size="12"><tspan font-weight="700" style="fill:var(--accent)">5</tspan><tspan style="fill:var(--text)"> &#183; submit composite once seen</tspan></text>

    <rect x="52"  y="248" width="244" height="138" rx="12" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#fence-shadow)"/>
    <text x="174" y="274" text-anchor="middle" style="fill:var(--text)" font-size="14" font-weight="600">Producer GPU</text>
    <text x="174" y="302" text-anchor="middle" font-size="12"><tspan font-weight="700" style="fill:var(--accent)">2</tspan><tspan style="fill:var(--text)"> &#183; execute all draws</tspan></text>
    <text x="174" y="328" text-anchor="middle" font-size="12"><tspan font-weight="700" style="fill:var(--accent)">3</tspan><tspan style="fill:var(--text)"> &#183; write timeline value</tspan></text>
    <text x="174" y="348" text-anchor="middle" style="fill:var(--text-muted)" font-size="9.5" font-style="italic">ordered after the draws</text>
    <text x="174" y="366" text-anchor="middle" style="fill:var(--text-muted)" font-size="9.5">seeing it &#8658; draws are done</text>

    <rect x="464" y="248" width="244" height="138" rx="12" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.5" filter="url(#fence-shadow)"/>
    <text x="586" y="274" text-anchor="middle" style="fill:var(--text)" font-size="14" font-weight="600">Consumer GPU</text>
    <text x="586" y="302" text-anchor="middle" font-size="12"><tspan font-weight="700" style="fill:var(--accent)">6</tspan><tspan style="fill:var(--text)"> &#183; composite shared texture</tspan></text>
    <text x="586" y="322" text-anchor="middle" style="fill:var(--text-muted)" font-size="9.5">into the final scanout image</text>
    <text x="586" y="344" text-anchor="middle" style="fill:var(--text-muted)" font-size="9.5">safe &#8212; draws already done</text>

    <!-- Shared memory (center, mapped by both) -->
    <rect x="312" y="120" width="136" height="252" rx="12" style="fill:var(--surface-sunken);stroke:var(--border)" stroke-width="1.5"/>
    <text x="380" y="144" text-anchor="middle" style="fill:var(--text)" font-size="13" font-weight="600">Shared memory</text>
    <text x="380" y="162" text-anchor="middle" style="fill:var(--text-faint)" font-size="9">UMA &#183; mapped by both</text>
    <rect x="326" y="186" width="108" height="46" rx="8" style="fill:var(--accent-tint);stroke:var(--accent)" stroke-width="1.5"/>
    <text x="380" y="206" text-anchor="middle" style="fill:var(--accent)" font-size="11" font-weight="700">timeline value</text>
    <text x="380" y="222" text-anchor="middle" style="fill:var(--text-muted)" font-size="9">the fence</text>
    <rect x="326" y="286" width="108" height="46" rx="8" style="fill:var(--surface-raised);stroke:var(--border)" stroke-width="1.25"/>
    <text x="380" y="306" text-anchor="middle" style="fill:var(--text)" font-size="11" font-weight="500">shared texture</text>
    <text x="380" y="322" text-anchor="middle" style="fill:var(--text-muted)" font-size="9">rendered pixels</text>

    <!-- Submit arrows (CPU queues work to its GPU) -->
    <path d="M 174 196 L 174 244" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#fence-arrow)"/>
    <path d="M 586 196 L 586 244" style="fill:none;stroke:var(--text-faint)" stroke-width="2" marker-end="url(#fence-arrow)"/>

    <!-- Fence path (accent): GPU writes value, CPU observes it -->
    <path d="M 294 320 L 328 230" style="fill:none;stroke:var(--accent)" stroke-width="2.25" marker-end="url(#fence-arrow-accent)"/>
    <path d="M 436 200 L 462 152" style="fill:none;stroke:var(--accent)" stroke-width="2.25" marker-end="url(#fence-arrow-accent)"/>

    <!-- Texture path (faint): produced then consumed -->
    <path d="M 294 352 L 328 308" style="fill:none;stroke:var(--text-faint)" stroke-width="1.75" marker-end="url(#fence-arrow)"/>
    <path d="M 436 308 L 462 348" style="fill:none;stroke:var(--text-faint)" stroke-width="1.75" marker-end="url(#fence-arrow)"/>
  </svg>
</div>

The way our emulated fence works is as follows: the producer calls `ID3D11DeviceContext::ClearUnorderedAccessViewUint` with an address in a shared memory buffer mapped by the consumer process. This API call lets us write an arbitrary integer to shared memory and we use it to write a timeline value. The write is done by the GPU so it is ordered with A's other draw calls meaning that when the timeline value write occurs in the GPU, we know that all the draws are complete. The consumer must poll on the shared memory (this must be done on the CPU because there is no memory value polling instruction on Apple GPUs). Once it sees the updated timeline value, it knows the draws are complete and that it is safe to consume the texture. The consumer CPU cannot queue its draw calls until it sees the fence event and therefore there is introduced latency while the GPU is potentially idle waiting for the next submission.

### D3DMetal

The last DirectX API implementation for macOS is made by Apple for the [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/). Originally designed for developers to test their Windows game on Apple Silicon, the GPT includes `D3DMetal.framework`, an implementation of D3D11 and D3D12 on top of Metal as well as a transpiler from DXBC/DXIL (Microsoft's proprietary GPU shader bytecode format) to AIR (Apple's proprietary GPU shader bytecode format). Just like DXMT, it is designed to work with Wine. Just like DXMT, it does not support shared textures or shared fences so we need to emulate them in the same way. However, unlike DXMT, it is not open source so we need to use swizzling and vtable patching to intercept API calls and change the output.

That is what we have done with [d3dmetal-native](https://github.com/utmapp/d3dmetal-native). It is a wrapper around `D3DMetal.framework` that allows it to work outside of Wine and support these additional features. Since we designed the API interface to be compatible with DXMT, we can easily switch between the two interfaces in virglrenderer. The result is a significant improvement in performance over DXMT.

[![Screenshot of FireStrike result with D3DMetal backend](/assets/images/posts/triton/windows-firestrike-d3dmetal.png)](/assets/images/posts/triton/windows-firestrike-d3dmetal.png){:target="_blank"}
*FireStrike (x64) for Windows 11 ARM64 running on macOS host with D3DMetal backend (Rosetta)*

Note that since D3DMetal only has an x86_64 slice (as it was intended for use with Rosetta + Wine), we have to run the entire `virgl_render_server` process in Rosetta. Even then it still outperforms DXMT running on native ARM64.

Unfortunately, D3DMetal's licence terms explicitly prohibits usage outside of the "sole purpose of developing, testing, or evaluating video games for use on Apple-branded products" and that it can only be distributed "solely for non-commercial purposes." That means we cannot include D3DMetal as part of a bundled application. Curiously, [CrossOver, a commercial Wine distribution, does bundle D3DMetal](https://support.codeweavers.com/en_US/miscellanous/advanced-settings-in-crossover-mac-26) and I was told that they have a special agreement with Apple in order to do this. If anyone is familiar with this arrangement, please contact us because we would love to include D3DMetal in UTM due to the improvement in performance.

# Try it out

All the work described here is open source so if you like tinkering, you can try it out and give us your feedback. We are actively working to upstream as much of these changes as possible and we will update UTM soon to support these features so anyone can try it without having to compile multiple projects.

**Hint:** Point your AI to this page and ask it to set it up for you.

## Code

* [QEMU](https://github.com/utmapp/qemu/tree/utm-edition-neptune)
* [virglrenderer](https://github.com/utmapp/virglrenderer/tree/neptune)
* [DXMT](https://github.com/utmapp/dxmt)
* [d3dmetal-native](https://github.com/utmapp/d3dmetal-native)
* [Windows UMD](https://github.com/osy/virtio-win-mesa/tree/neptune)
* [Windows KMD](https://github.com/osy/kvm-guest-drivers-windows/tree/neptune)
* [Windows driver build scripts](https://github.com/osy/build-mesa)

## Building (macOS)

These build instructions are specific for macOS. The build instructions for Linux are largely [unchanged from the previous post]({% post_url 2026-05-16-introducing-neptune-direct3d-virtualization-for-qemu %}#building).

Everything installs into one staging prefix, and the pieces find each other through that prefix's `pkgconfig` directory, so set these first and keep them for the whole session:
{:.author-ai}

```bash
export SRC=/path/to/checkouts       # where the git repositories live
export PREFIX=/path/to/prefix       # staging install root: bin/ lib/ libexec/ share/
export ANGLE_INC="$SRC/WebKit/Source/ThirdParty/ANGLE/include"
export ANGLE_LIB="$PREFIX/ANGLE.xcarchive/Products/usr/local/lib"
```
{:.author-ai}

You will need Xcode (with the Metal toolchain) and the command line tools, Meson 1.3+, Ninja, `pkg-config`, CMake, and an **LLVM 15** installation (exact major version, with headers and static libraries) for DXMT.
{:.author-ai}

### ANGLE and libepoxy

QEMU's `-display cocoa,gl=es` path and virglrenderer's GL backend go through ANGLE-on-Metal, which the WebKit tree builds, plus a libepoxy that dispatches to it. This is unchanged from the Venus work but it is a prerequisite for everything else.
{:.author-ai}

```bash
git clone --filter=tree:0 --no-checkout https://github.com/utmapp/WebKit.git "$SRC/WebKit"
git -C "$SRC/WebKit" sparse-checkout init
git -C "$SRC/WebKit" sparse-checkout set Source/ThirdParty/ANGLE Configurations Tools/ccache
git -C "$SRC/WebKit" checkout 6a7f464047e2f6f2b65fe315aaad5d1ff3229cb7
cd "$SRC/WebKit/Source/ThirdParty/ANGLE"
xcodebuild archive \
  -archivePath "$PREFIX/ANGLE" \
  -scheme ANGLE \
  -sdk macosx \
  -arch arm64 \
  -configuration Release \
  WEBCORE_LIBRARY_DIR=/usr/local/lib \
  NORMAL_UMBRELLA_FRAMEWORKS_DIR="" \
  CODE_SIGNING_ALLOWED=NO \
  MACOSX_DEPLOYMENT_TARGET=11.0
```
{:.author-ai}

```bash
git clone -b macos-venus https://github.com/utmapp/libepoxy.git "$SRC/libepoxy"
meson setup "$SRC/libepoxy/build" "$SRC/libepoxy" \
  "-Dc_args=-I$ANGLE_INC" \
  -Degl=yes \
  -Dx11=false \
  "--prefix=$PREFIX"
meson install -C "$SRC/libepoxy/build"
```
{:.author-ai}

### DXMT

DXMT builds as a Wine cross build by default; passing no cross file gives the native build, which links every module into a single `libdxmt-native.dylib` exporting the D3D11/DXGI entry points plus the embedder API (Win32-style events and shared textures) that the Neptune render server uses.
{:.author-ai}

```bash
export LLVM15=/path/to/llvm@15   # arm64 LLVM 15 install root
git clone https://github.com/utmapp/dxmt.git "$SRC/dxmt"
cd "$SRC/dxmt"
meson setup build-native \
  "-Dnative_llvm_path=$LLVM15" \
  --buildtype=release \
  "--prefix=$PREFIX"
meson install -C build-native
```
{:.author-ai}

Homebrew's `llvm@15` works for `$LLVM15`; DXMT's `docs/DEVELOPMENT.md` also documents building it from source.
{:.author-ai}

### d3dmetal-native

`D3DMetal.framework` ships as x86_64 only, so this library — and every process that loads it — must be x86_64. The cross file that selects `-arch x86_64` is in the repository, and Rosetta 2 runs the results (including the test suite) transparently.
{:.author-ai}

```bash
git clone https://github.com/utmapp/d3dmetal-native.git "$SRC/d3dmetal-native"
cd "$SRC/d3dmetal-native"
meson setup build \
  --cross-file build-macos-x86_64.txt \
  -Dtests=disabled \
  "--prefix=$PREFIX"
meson install -C build
```
{:.author-ai}

The framework itself is not bundled: get it from Apple's Game Porting Toolkit and point the library at it at runtime with `D3DMETAL_FRAMEWORK_PATH` (or compile in a fallback with `-Ddev_framework_path=...`). If macOS quarantines it, `xattr -dr com.apple.quarantine D3DMetal.framework`.
{:.author-ai}

### virglrenderer

This is the interesting one, because a single QEMU process has to drive a native arm64 library and two render servers of *different architectures*. It is three Meson configurations of the same source tree:
{:.author-ai}

1. **arm64 library** (`neptune-mode=client`) — the `libvirglrenderer` that QEMU links. It advertises the Neptune capset and proxies D3D traffic to the render server without linking any D3D backend, which is what lets the library stay native arm64 while a backend runs elsewhere. This is the only configuration that gets installed.
2. **arm64 render server** (`neptune-mode=server`) — hosts Venus and the Neptune DXMT backend.
3. **x86_64 render server** (`neptune-mode=server`, cross-compiled) — hosts the Neptune D3DMetal backend.
{:.author-ai}

The two servers are then fused with `lipo` into one universal binary. At runtime the parent process picks a worker's slice per context, so there is only one render server path to configure.
{:.author-ai}

```bash
git clone -b neptune https://github.com/utmapp/virglrenderer.git "$SRC/virglrenderer"
```
{:.author-ai}

**1. Native arm64 library (client mode).**
{:.author-ai}

```bash
meson setup "$SRC/virglrenderer/build-arm64" "$SRC/virglrenderer" \
  "-Dc_args=-I$ANGLE_INC" \
  -Dvenus=true \
  -Dneptune=true \
  -Dneptune-mode=client \
  -Drender-server-worker=process \
  -Dcheck-gl-errors=false \
  "--pkg-config-path=$PREFIX/lib/pkgconfig" \
  "--prefix=$PREFIX"
meson install -C "$SRC/virglrenderer/build-arm64"
```
{:.author-ai}

**2. Native arm64 render server (Venus + Neptune/DXMT).** Same options with `neptune-mode=server`. Only compile it — installing would overwrite the client library from step 1.
{:.author-ai}

```bash
meson setup "$SRC/virglrenderer/build-arm64-server" "$SRC/virglrenderer" \
  "-Dc_args=-I$ANGLE_INC" \
  -Dvenus=true \
  -Dneptune=true \
  -Dneptune-mode=server \
  -Drender-server-worker=process \
  -Dcheck-gl-errors=false \
  "--pkg-config-path=$PREFIX/lib/pkgconfig" \
  "--prefix=$PREFIX"
meson compile -C "$SRC/virglrenderer/build-arm64-server"
```
{:.author-ai}

**3. Rosetta x86_64 render server (Neptune/D3DMetal).** This one cross-compiles with the cross file from the d3dmetal-native repository. Since ANGLE was built arm64, the x86_64 configuration must not try to use EGL, so give it its own pkg-config directory with EGL turned off:
{:.author-ai}

```bash
cp -R "$PREFIX/lib/pkgconfig" "$PREFIX/lib/pkgconfig-x86_64"
sed -i '' 's/epoxy_has_egl=1/epoxy_has_egl=0/' "$PREFIX/lib/pkgconfig-x86_64/epoxy.pc"
meson setup "$SRC/virglrenderer/build-x86_64-server" "$SRC/virglrenderer" \
  --cross-file "$SRC/d3dmetal-native/build-macos-x86_64.txt" \
  "-Dc_args=-I$ANGLE_INC" \
  -Dvenus=false \
  -Dneptune=true \
  -Dneptune-mode=server \
  -Drender-server-worker=process \
  -Dcheck-gl-errors=false \
  "--pkg-config-path=$PREFIX/lib/pkgconfig-x86_64" \
  "--prefix=$PREFIX"
meson compile -C "$SRC/virglrenderer/build-x86_64-server"
```
{:.author-ai}

**4. Fuse the two slices.**
{:.author-ai}

```bash
lipo -create \
  "$SRC/virglrenderer/build-arm64-server/server/virgl_render_server" \
  "$SRC/virglrenderer/build-x86_64-server/server/virgl_render_server" \
  -output "$PREFIX/libexec/virgl_render_server"
lipo -archs "$PREFIX/libexec/virgl_render_server"   # must print: x86_64 arm64
```
{:.author-ai}

Neither backend is linked: the render server `dlopen`s `libdxmt-native.dylib` on the arm64 slice and `libd3dmetal-native.dylib` on the x86_64 slice, by name, so both must be reachable through the dynamic loader path at run time (see [Running](#running)).
{:.author-ai}

### QEMU

Nothing Neptune-specific has to be enabled at configure time — virglrenderer is picked up through `pkg-config`, so point `PKG_CONFIG_PATH` at the prefix you just installed it into:
{:.author-ai}

```bash
git clone -b utm-edition-neptune https://github.com/utmapp/qemu.git "$SRC/qemu"
mkdir -p "$SRC/qemu/build" && cd "$SRC/qemu/build"
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" ../configure \
  "--extra-cflags=-I$ANGLE_INC" \
  "--extra-ldflags=-L$ANGLE_LIB" \
  "--prefix=$PREFIX" \
  --target-list=aarch64-softmmu
make -j"$(getconf _NPROCESSORS_ONLN)" install
```
{:.author-ai}

The configure summary should report `virglrenderer: YES` and `Cocoa: YES`; if virglrenderer is missing, the `-device virtio-gpu-gl-pci` line below will fail with an unknown device. `make install` also puts the UEFI firmware in `$PREFIX/share/qemu`; make the VM its own writable copy of the variable store from `pc-bios/edk2-arm-vars.fd` in the build directory.
{:.author-ai}

## Building (Windows drivers)

You need a Windows machine (or VM) to build the Windows drivers. Full instructions [are here](https://github.com/osy/kvm-guest-drivers-windows/blob/neptune/viogpu/viogpu3d/BUILDING.md) and you may want to use [build-mesa](https://github.com/osy/build-mesa) for the UMD which simplifies the build process. If you just want to test the driver, we have [pre-built signed drivers available](https://github.com/osy/kvm-guest-drivers-windows/releases). **Note these drivers are still very unstable and you should not install them on any VM that you care about!**

## Running

You need a Windows ARM64 guest (you can find instructions to build an image elsewhere or you can use UTM and copy the disk image). `sudo` is only needed for bridged (`vmnet`) networking — with user networking QEMU runs fine unprivileged.
{:.author-ai}

```bash
export VM=/path/to/vm                    # disk image + EFI variable store
export D3DMETAL=/path/to/D3DMetal.framework
D3DMETAL_FRAMEWORK_PATH="$D3DMETAL" \
DYLD_FALLBACK_LIBRARY_PATH="$PREFIX/lib:$ANGLE_LIB" \
ANGLE_DEFAULT_PLATFORM=metal \
VIRGL_LOG_LEVEL=debug \
"$PREFIX/bin/qemu-system-aarch64" \
  -machine virt \
  -accel hvf,ipa-granule-size=0x1000 \
  -cpu host \
  -smp cpus=4,sockets=1,cores=4,threads=1 \
  -m 4096 \
  -nodefaults \
  -vga none \
  -device virtio-ramfb-gl,hostmem=8G,blob=true,venus=true,neptune=true \
  -display cocoa,gl=es \
  -drive if=pflash,format=raw,unit=0,file.filename="$PREFIX/share/qemu/edk2-aarch64-code.fd",readonly=on \
  -drive if=pflash,unit=1,file.filename="$VM/efi_vars.fd" \
  -device nvme,drive=disk,serial=disk,bootindex=1 \
  -drive if=none,media=disk,id=disk,file.filename="$VM/windows.qcow2",discard=unmap,detect-zeroes=unmap \
  -device nec-usb-xhci,id=usb-bus \
  -device usb-tablet,bus=usb-bus.0 \
  -device usb-kbd,bus=usb-bus.0 \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22
```
{:.author-ai}

The arguments that matter for graphics:
{:.author-ai}

* `-device virtio-ramfb-gl,hostmem=8G,blob=true,venus=true,neptune=true` — `neptune=true` advertises the Neptune capset (`venus=true` additionally advertises Venus for guest Vulkan). `blob=true` plus a `hostmem` window is **required**.
* `-accel hvf,ipa-granule-size=0x1000` — HVF maps guest memory at this granularity. The 4KiB pages are required by Venus and optional for Neptune.
* `-display cocoa,gl=es` — the Cocoa window scans out through ANGLE/Metal until Triton's scanout blob engages.
* `virtio-ramfb-gl` is a device that only exists in the UTM fork of QEMU and presents Windows with a POST display that can be used before any drivers are installed. If you are porting this to vanilla QEMU, you can use `ramfb`, install the drivers, then change to `virtio-gpu-gl-pci` and reboot.
{:.author-ai}

### Environment variables

| Variable | Effect |
| --- | --- |
| `DYLD_FALLBACK_LIBRARY_PATH` | How QEMU finds `libvirglrenderer`, and how the render server finds `libdxmt-native.dylib` / `libd3dmetal-native.dylib` — both are `dlopen`ed by plain name, so the prefix's `lib` directory must be on this path. |
| `RENDER_SERVER_EXEC_PATH` | Overrides the render server binary; defaults to the `libexec` path baked in at build time. |
| `NPT_BACKEND` | `d3dmetal` (default) or `dxmt`. This selects which *slice* of the universal render server a Neptune worker is spawned as: x86_64 under Rosetta for D3DMetal, native arm64 for DXMT. |
| `D3DMETAL_FRAMEWORK_PATH` | Where `libd3dmetal-native.dylib` looks for `D3DMetal.framework`. Without it, it searches next to the dylib and in a sibling `Frameworks` directory. |
| `NPT_D3D11_LIBRARY_PATH`, `NPT_DXGI_LIBRARY_PATH`, `NPT_D3D12_LIBRARY_PATH` | Override the backend dylib loaded for each D3D interface. Useful to point at a build tree instead of the installed copy. |
| `NPT_WA_FLAGS` | Bitmask forcing the host-side workaround set (shader signature synthesis and friends). `NPT_WA_FLAGS=0` disables all of them to see raw backend behavior. |
| `VIRGL_LOG_LEVEL` / `VIRGL_LOG_FILE` | Host renderer logging. `debug` is what surfaces the `npt:` lines from the Neptune host module; they go to QEMU's stdout unless a log file is set. |
| `DMN_LOG`, `DXMT_LOG_LEVEL` | Per-backend logging for d3dmetal-native and DXMT respectively. |
| `VK_DRIVER_FILES` | MoltenVK ICD, only needed if you also want Venus (guest Vulkan) working alongside Triton. |
{:.author-ai}

