// Diagram assets for the knowledge base. Kept apart from the viewer so the app
// shell stays readable; benchmark/generate_knowledge_page.dart splices this
// file into the template's diagram placeholder.
const DG_DEFS = `<defs>
  <marker id="ah-ok" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,1 L7,4 L0,7 Z" fill="var(--ok)"/></marker>
  <marker id="ah-meas" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,1 L7,4 L0,7 Z" fill="var(--meas)"/></marker>
  <marker id="ah-acc" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,1 L7,4 L0,7 Z" fill="var(--accent)"/></marker>
  <marker id="ah-st" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,1 L7,4 L0,7 Z" fill="var(--stale)"/></marker>
  <marker id="ah-ink" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,1 L7,4 L0,7 Z" fill="var(--ink-2)"/></marker>
</defs>`;
const DIAGRAMS = {
  boundary: `<figure class="diagram-card"><svg viewBox="0 0 900 336" width="100%" role="img" aria-label="Four transfer routes across the isolate boundary, by cost">
    ${DG_DEFS}
    <rect x="18" y="40" width="250" height="272" class="dg-box"/>
    <rect x="632" y="40" width="250" height="272" class="dg-box"/>
    <text x="143" y="28" text-anchor="middle" class="dg-zone">MAIN ISOLATE</text>
    <text x="757" y="28" text-anchor="middle" class="dg-zone">WORKER ISOLATES</text>
    <line x1="330" y1="16" x2="330" y2="326" class="dg-wall"/><line x1="570" y1="16" x2="570" y2="326" class="dg-wall"/>
    <text x="450" y="28" text-anchor="middle" class="dg-zone" fill="var(--stale)">BOUNDARY</text>
    <text x="450" y="72" text-anchor="middle" class="dg-flow">strings &amp; numbers</text>
    <line x1="285" y1="84" x2="615" y2="84" stroke="var(--ok)" stroke-width="2.4" marker-end="url(#ah-ok)" marker-start="url(#ah-ok)"/>
    <text x="450" y="100" text-anchor="middle" class="dg-cost">shared by pointer · free at any size</text>
    <text x="450" y="136" text-anchor="middle" class="dg-flow">result structure — the flat values list</text>
    <line x1="615" y1="148" x2="288" y2="148" stroke="var(--meas)" stroke-width="2.4" marker-end="url(#ah-meas)"/>
    <text x="450" y="164" text-anchor="middle" class="dg-cost">send() · deep-copied per slot · the real price of a result</text>
    <text x="450" y="200" text-anchor="middle" class="dg-flow">blobs ≥ 256 KB &nbsp;·&nbsp; both directions</text>
    <line x1="288" y1="212" x2="615" y2="212" stroke="var(--accent)" stroke-width="2.4" marker-end="url(#ah-acc)" marker-start="url(#ah-acc)"/>
    <text x="450" y="228" text-anchor="middle" class="dg-cost">TransferableTypedData · one copy → external memory · then ownership move</text>
    <text x="450" y="264" text-anchor="middle" class="dg-flow">results &gt; 32k slots</text>
    <line x1="615" y1="276" x2="288" y2="276" stroke="var(--stale)" stroke-width="2.4" marker-end="url(#ah-st)"/>
    <text x="450" y="292" text-anchor="middle" class="dg-cost">Isolate.exit · whole heap, no copy · worker dies, pool respawns</text>
    <text x="450" y="320" text-anchor="middle" class="dg-cost">slots, not bytes — a 400 KB string is 1 slot and was never going to be copied</text>
  </svg><figcaption>the four routes across, ordered by what they cost</figcaption></figure>`,

  api: `<figure class="diagram-card"><svg viewBox="0 0 900 300" width="100%" role="img" aria-label="Public API request paths from the main isolate">
    ${DG_DEFS}
    <rect x="18" y="34" width="200" height="240" class="dg-box"/>
    <text x="118" y="24" text-anchor="middle" class="dg-zone">MAIN ISOLATE</text>
    <text x="118" y="62" text-anchor="middle" class="dg-flow">Database</text>
    <text x="118" y="92" text-anchor="middle" class="dg-cost">select · selectBytes</text>
    <text x="118" y="112" text-anchor="middle" class="dg-cost">execute · executeBatch</text>
    <text x="118" y="132" text-anchor="middle" class="dg-cost">transaction · stream</text>
    <rect x="42" y="164" width="152" height="86" rx="7" fill="none" stroke="var(--meas)" stroke-dasharray="4 3"/>
    <text x="118" y="184" text-anchor="middle" class="dg-flow">StreamEngine</text>
    <text x="118" y="204" text-anchor="middle" class="dg-cost">table → entry index</text>
    <text x="118" y="222" text-anchor="middle" class="dg-cost">requery queue</text>
    <text x="118" y="240" text-anchor="middle" class="dg-cost">per-subscriber ctrls</text>
    <line x1="222" y1="96" x2="392" y2="80" stroke="var(--ok)" stroke-width="2" marker-end="url(#ah-ok)"/>
    <text x="306" y="74" text-anchor="middle" class="dg-cost">reads</text>
    <line x1="222" y1="118" x2="392" y2="168" stroke="var(--accent)" stroke-width="2" marker-end="url(#ah-acc)"/>
    <text x="300" y="150" text-anchor="middle" class="dg-cost">writes</text>
    <rect x="396" y="52" width="180" height="58" class="dg-box"/>
    <text x="486" y="76" text-anchor="middle" class="dg-flow">Reader pool</text>
    <text x="486" y="96" text-anchor="middle" class="dg-cost">2–4 workers</text>
    <rect x="396" y="140" width="180" height="58" class="dg-box"/>
    <text x="486" y="164" text-anchor="middle" class="dg-flow">Writer isolate</text>
    <text x="486" y="184" text-anchor="middle" class="dg-cost">serial, owns tx state</text>
    <rect x="640" y="86" width="230" height="112" class="dg-box"/>
    <text x="755" y="76" text-anchor="middle" class="dg-zone">C CONNECTION POOL</text>
    <text x="755" y="112" text-anchor="middle" class="dg-cost">1 writer + N readers</text>
    <text x="755" y="132" text-anchor="middle" class="dg-cost">statement caches</text>
    <text x="755" y="152" text-anchor="middle" class="dg-cost">authorizer hook → deps read</text>
    <text x="755" y="172" text-anchor="middle" class="dg-cost">preupdate hook → tables dirtied</text>
    <line x1="580" y1="81" x2="636" y2="110" stroke="var(--ink-2)" stroke-width="1.6" marker-end="url(#ah-ink)"/>
    <line x1="580" y1="169" x2="636" y2="150" stroke="var(--ink-2)" stroke-width="1.6" marker-end="url(#ah-ink)"/>
    <path d="M 486 198 C 486 250, 200 262, 130 254" fill="none" stroke="var(--stale)" stroke-width="1.8" stroke-dasharray="5 4" marker-end="url(#ah-st)"/>
    <text x="330" y="272" text-anchor="middle" class="dg-cost">dirty tables ride back on the write response — no separate channel</text>
  </svg><figcaption>one message per call; invalidation piggybacks on write replies</figcaption></figure>`,

  readers: `<figure class="diagram-card"><svg viewBox="0 0 900 292" width="100%" role="img" aria-label="Reader pool dispatch and sacrifice lifecycle">
    ${DG_DEFS}
    <text x="96" y="40" text-anchor="middle" class="dg-zone">DISPATCH</text>
    <rect x="24" y="56" width="146" height="72" class="dg-box"/>
    <text x="97" y="82" text-anchor="middle" class="dg-flow">round-robin</text>
    <text x="97" y="102" text-anchor="middle" class="dg-cost">+ busy tracking</text>
    <text x="97" y="118" text-anchor="middle" class="dg-cost">FIFO park when full</text>
    <text x="420" y="40" text-anchor="middle" class="dg-zone">FOUR PERSISTENT WORKERS</text>
    <rect x="212" y="56" width="98" height="52" class="dg-box"/><text x="261" y="86" text-anchor="middle" class="dg-cost">worker 0</text>
    <rect x="320" y="56" width="98" height="52" class="dg-box"/><text x="369" y="86" text-anchor="middle" class="dg-cost">worker 1</text>
    <rect x="428" y="56" width="98" height="52" class="dg-box"/><text x="477" y="86" text-anchor="middle" class="dg-cost">worker 2</text>
    <rect x="536" y="56" width="98" height="52" class="dg-box" stroke="var(--stale)"/><text x="585" y="80" text-anchor="middle" class="dg-cost" fill="var(--stale)">worker 3</text>
    <text x="585" y="98" text-anchor="middle" class="dg-cost" fill="var(--stale)">sacrificed</text>
    <line x1="174" y1="82" x2="208" y2="82" stroke="var(--ink-2)" stroke-width="1.6" marker-end="url(#ah-ink)"/>
    <rect x="676" y="46" width="200" height="72" class="dg-box"/>
    <text x="776" y="40" text-anchor="middle" class="dg-zone">C READER CONNECTIONS</text>
    <text x="776" y="74" text-anchor="middle" class="dg-cost">one per worker · NOMUTEX</text>
    <text x="776" y="94" text-anchor="middle" class="dg-cost">statement cache survives</text>
    <text x="776" y="110" text-anchor="middle" class="dg-cost">the worker's death</text>
    <line x1="638" y1="82" x2="672" y2="82" stroke="var(--ink-2)" stroke-width="1.6" marker-end="url(#ah-ink)"/>
    <text x="450" y="164" text-anchor="middle" class="dg-zone">RESULT LEAVES BY ONE OF TWO ROUTES</text>
    <line x1="250" y1="196" x2="640" y2="196" stroke="var(--meas)" stroke-width="2.2" marker-end="url(#ah-meas)" marker-start="url(#ah-meas)"/>
    <text x="445" y="190" text-anchor="middle" class="dg-flow">≤ 32k slots → SendPort.send</text>
    <text x="445" y="212" text-anchor="middle" class="dg-cost">worker survives · pays a per-slot copy before its next request</text>
    <line x1="250" y1="252" x2="640" y2="252" stroke="var(--stale)" stroke-width="2.2" marker-end="url(#ah-st)"/>
    <text x="445" y="246" text-anchor="middle" class="dg-flow">&gt; 32k slots → Isolate.exit</text>
    <text x="445" y="268" text-anchor="middle" class="dg-cost">zero copy · worker dies · replacement spawns in background, slot returns on handshake</text>
    <text x="445" y="286" text-anchor="middle" class="dg-cost">payload and exit share one port, so FIFO ordering makes the handoff race-free</text>
  </svg><figcaption>dispatch, the two return routes, and what survives a sacrifice</figcaption></figure>`,

  writer: `<figure class="diagram-card"><svg viewBox="0 0 900 268" width="100%" role="img" aria-label="Writer isolate serial pipeline">
    ${DG_DEFS}
    <text x="120" y="34" text-anchor="middle" class="dg-zone">MAIN ISOLATE</text>
    <rect x="24" y="48" width="192" height="128" class="dg-box"/>
    <text x="120" y="72" text-anchor="middle" class="dg-cost">execute × N concurrent</text>
    <rect x="44" y="86" width="152" height="34" rx="6" fill="none" stroke="var(--accent)" stroke-dasharray="4 3"/>
    <text x="120" y="107" text-anchor="middle" class="dg-flow">coalescing pump</text>
    <text x="120" y="140" text-anchor="middle" class="dg-cost">one envelope</text>
    <text x="120" y="158" text-anchor="middle" class="dg-cost">per round trip</text>
    <line x1="220" y1="112" x2="300" y2="112" stroke="var(--accent)" stroke-width="2.2" marker-end="url(#ah-acc)"/>
    <text x="260" y="104" text-anchor="middle" class="dg-cost">params wrapped</text>
    <text x="260" y="130" text-anchor="middle" class="dg-cost">by identity</text>
    <line x1="300" y1="26" x2="300" y2="254" class="dg-wall"/>
    <text x="600" y="34" text-anchor="middle" class="dg-zone">WRITER ISOLATE — SERIAL</text>
    <rect x="320" y="48" width="250" height="128" class="dg-box"/>
    <text x="445" y="74" text-anchor="middle" class="dg-flow">message loop</text>
    <text x="445" y="96" text-anchor="middle" class="dg-cost">Execute · Query · Batch</text>
    <text x="445" y="114" text-anchor="middle" class="dg-cost">Begin · Commit · Rollback</text>
    <text x="445" y="140" text-anchor="middle" class="dg-cost">unwrap blobs (once per</text>
    <text x="445" y="156" text-anchor="middle" class="dg-cost">unique buffer) → bind</text>
    <rect x="600" y="48" width="272" height="128" class="dg-box"/>
    <text x="736" y="74" text-anchor="middle" class="dg-flow">C write connection</text>
    <text x="736" y="98" text-anchor="middle" class="dg-cost">executeBatch: whole matrix</text>
    <text x="736" y="114" text-anchor="middle" class="dg-cost">loops inside C, one crossing</text>
    <text x="736" y="140" text-anchor="middle" class="dg-cost">preupdate hook accumulates</text>
    <text x="736" y="156" text-anchor="middle" class="dg-cost">dirty tables</text>
    <line x1="574" y1="112" x2="596" y2="112" stroke="var(--ink-2)" stroke-width="1.6" marker-end="url(#ah-ink)"/>
    <path d="M 736 180 C 736 232, 300 244, 130 232" fill="none" stroke="var(--stale)" stroke-width="1.8" stroke-dasharray="5 4" marker-end="url(#ah-st)"/>
    <text x="430" y="252" text-anchor="middle" class="dg-cost">WriteResult + dirty tables return together — stream invalidation costs no extra message</text>
  </svg><figcaption>concurrent writes in, one serial pipeline, invalidation on the way back</figcaption></figure>`,

  tx: `<figure class="diagram-card"><svg viewBox="0 0 900 258" width="100%" role="img" aria-label="Transaction round trips between main isolate and writer">
    ${DG_DEFS}
    <text x="150" y="30" text-anchor="middle" class="dg-zone">MAIN ISOLATE — CALLBACK RUNS HERE</text>
    <text x="700" y="30" text-anchor="middle" class="dg-zone">WRITER ISOLATE</text>
    <line x1="300" y1="40" x2="300" y2="242" class="dg-wall"/>
    <line x1="150" y1="44" x2="150" y2="238" stroke="var(--line)" stroke-width="1.5"/>
    <line x1="700" y1="44" x2="700" y2="238" stroke="var(--line)" stroke-width="1.5"/>
    <text x="150" y="62" text-anchor="middle" class="dg-cost">db.transaction((tx) async {</text>
    <line x1="158" y1="88" x2="692" y2="88" stroke="var(--accent)" stroke-width="1.8" marker-end="url(#ah-acc)"/>
    <text x="425" y="82" text-anchor="middle" class="dg-cost">BEGIN</text>
    <line x1="158" y1="120" x2="692" y2="120" stroke="var(--accent)" stroke-width="1.8" marker-end="url(#ah-acc)"/>
    <text x="425" y="114" text-anchor="middle" class="dg-cost">tx.execute — one round trip</text>
    <line x1="692" y1="140" x2="158" y2="140" stroke="var(--ink-2)" stroke-width="1.4" stroke-dasharray="3 3" marker-end="url(#ah-ink)"/>
    <line x1="158" y1="168" x2="692" y2="168" stroke="var(--meas)" stroke-width="1.8" marker-end="url(#ah-meas)"/>
    <text x="425" y="162" text-anchor="middle" class="dg-cost">tx.select — on the WRITER connection (sees uncommitted rows)</text>
    <line x1="692" y1="188" x2="158" y2="188" stroke="var(--ink-2)" stroke-width="1.4" stroke-dasharray="3 3" marker-end="url(#ah-ink)"/>
    <line x1="158" y1="216" x2="692" y2="216" stroke="var(--ok)" stroke-width="1.8" marker-end="url(#ah-ok)"/>
    <text x="425" y="210" text-anchor="middle" class="dg-cost">COMMIT → accumulated dirty tables released to streams</text>
    <text x="150" y="238" text-anchor="middle" class="dg-cost">})</text>
    <text x="450" y="252" text-anchor="middle" class="dg-cost" fill="var(--stale)">each statement is one round trip — that floor dominates every control-path optimization</text>
  </svg><figcaption>the callback stays on main; the round-trip floor is the subsystem's ceiling</figcaption></figure>`,

  native: `<figure class="diagram-card"><svg viewBox="0 0 900 262" width="100%" role="img" aria-label="Native C layer structure">
    ${DG_DEFS}
    <text x="450" y="28" text-anchor="middle" class="dg-zone">native/resqlite.c — STATE THAT OUTLIVES EVERY DART ISOLATE</text>
    <rect x="24" y="44" width="250" height="118" class="dg-box"/>
    <text x="149" y="68" text-anchor="middle" class="dg-flow">connection pool</text>
    <text x="149" y="90" text-anchor="middle" class="dg-cost">1 writer + N readers</text>
    <text x="149" y="108" text-anchor="middle" class="dg-cost">per-connection stmt cache</text>
    <text x="149" y="126" text-anchor="middle" class="dg-cost">NOMUTEX → one lock</text>
    <text x="149" y="144" text-anchor="middle" class="dg-cost">per query, not per call</text>
    <rect x="292" y="44" width="250" height="118" class="dg-box"/>
    <text x="417" y="68" text-anchor="middle" class="dg-flow">batched decode</text>
    <text x="417" y="90" text-anchor="middle" class="dg-cost">resqlite_step_row fills a</text>
    <text x="417" y="108" text-anchor="middle" class="dg-cost">whole row of cells at once</text>
    <text x="417" y="126" text-anchor="middle" class="dg-cost">one FFI crossing per row,</text>
    <text x="417" y="144" text-anchor="middle" class="dg-cost">not one per column</text>
    <rect x="560" y="44" width="316" height="118" class="dg-box"/>
    <text x="718" y="68" text-anchor="middle" class="dg-flow">encoders — where SIMD lives</text>
    <text x="718" y="90" text-anchor="middle" class="dg-cost">base64: NEON vqtbl4q_u8 (~2×), noinline,</text>
    <text x="718" y="106" text-anchor="middle" class="dg-cost">scalar 12-bit LUT fallback off ARM64</text>
    <text x="718" y="128" text-anchor="middle" class="dg-cost">integers: scalar itoa — per-cell SIMD has</text>
    <text x="718" y="144" text-anchor="middle" class="dg-cost">no batching to amortize its setup</text>
    <rect x="24" y="182" width="410" height="62" class="dg-box" stroke="var(--meas)"/>
    <text x="229" y="204" text-anchor="middle" class="dg-flow">hooks — reactivity without parsing SQL</text>
    <text x="229" y="224" text-anchor="middle" class="dg-cost">authorizer on readers → tables/columns read</text>
    <text x="229" y="240" text-anchor="middle" class="dg-cost">preupdate on writer → tables actually changed</text>
    <rect x="466" y="182" width="410" height="62" class="dg-box" stroke="var(--stale)"/>
    <text x="671" y="204" text-anchor="middle" class="dg-flow">WAL &amp; buffers</text>
    <text x="671" y="224" text-anchor="middle" class="dg-cost">checkpoint inline on writer (off-writer proven, parked)</text>
    <text x="671" y="240" text-anchor="middle" class="dg-cost">per-reader json_buf reclaims above 1 MB, high-water reported</text>
  </svg><figcaption>C owns the durable state; Dart isolates are replaceable workers over it</figcaption></figure>`,

  meta: `<figure class="diagram-card"><svg viewBox="0 0 900 244" width="100%" role="img" aria-label="How evidence becomes documentation and how it is invalidated">
    ${DG_DEFS}
    <rect x="24" y="56" width="184" height="76" class="dg-box"/>
    <text x="116" y="46" text-anchor="middle" class="dg-zone">EXPERIMENT</text>
    <text x="116" y="84" text-anchor="middle" class="dg-cost">order-flipped A/B</text>
    <text x="116" y="102" text-anchor="middle" class="dg-cost">drift flags · control lanes</text>
    <text x="116" y="120" text-anchor="middle" class="dg-cost">writeup + benchmark run</text>
    <line x1="212" y1="94" x2="256" y2="94" stroke="var(--ok)" stroke-width="2" marker-end="url(#ah-ok)"/>
    <rect x="260" y="56" width="184" height="76" class="dg-box"/>
    <text x="352" y="46" text-anchor="middle" class="dg-zone">CLAIM</text>
    <text x="352" y="84" text-anchor="middle" class="dg-cost">addressable id · dated</text>
    <text x="352" y="102" text-anchor="middle" class="dg-cost">conditions · typed edges</text>
    <text x="352" y="120" text-anchor="middle" class="dg-cost">state derived, never stored</text>
    <line x1="448" y1="94" x2="492" y2="94" stroke="var(--ok)" stroke-width="2" marker-end="url(#ah-ok)"/>
    <rect x="496" y="56" width="184" height="76" class="dg-box"/>
    <text x="588" y="46" text-anchor="middle" class="dg-zone">CHAPTER</text>
    <text x="588" y="84" text-anchor="middle" class="dg-cost">authored narrative</text>
    <text x="588" y="102" text-anchor="middle" class="dg-cost">[[claim]] citations inline</text>
    <text x="588" y="120" text-anchor="middle" class="dg-cost">never regenerated</text>
    <line x1="684" y1="94" x2="728" y2="94" stroke="var(--ok)" stroke-width="2" marker-end="url(#ah-ok)"/>
    <rect x="732" y="56" width="160" height="76" class="dg-box"/>
    <text x="812" y="46" text-anchor="middle" class="dg-zone">READERS</text>
    <text x="812" y="86" text-anchor="middle" class="dg-cost">humans: this page</text>
    <text x="812" y="106" text-anchor="middle" class="dg-cost">agents: the JSON</text>
    <text x="812" y="124" text-anchor="middle" class="dg-cost">same graph, two lenses</text>
    <path d="M 352 140 C 352 196, 500 200, 586 186" fill="none" stroke="var(--stale)" stroke-width="2" stroke-dasharray="5 4" marker-end="url(#ah-st)"/>
    <text x="352" y="164" text-anchor="middle" class="dg-flow" fill="var(--stale)">a later claim supersedes</text>
    <text x="612" y="192" text-anchor="start" class="dg-cost" fill="var(--stale)">→ citation renders struck-through immediately</text>
    <text x="612" y="210" text-anchor="start" class="dg-cost" fill="var(--stale)">→ CI reports repair debt on that chapter</text>
    <text x="450" y="234" text-anchor="middle" class="dg-cost">documentation auto-INVALIDATES; it never auto-updates — prose stays authored</text>
  </svg><figcaption>evidence becomes narrative; supersession makes the narrative flag itself</figcaption></figure>`,

  // The landing-page diagram. Deliberately the plainest of the set: it answers
  // "what talks to what" and nothing else, leaving cost and mechanism to the
  // subsystem pages that can afford the detail.
  overview: `<figure class="diagram-card wide"><svg viewBox="0 0 960 400" width="100%" role="img" aria-label="resqlite system overview: the main isolate calls into worker isolates across the isolate boundary, and workers talk to native SQLite">
    ${DG_DEFS}
    <text x="139" y="24" text-anchor="middle" class="dg-zone">MAIN ISOLATE</text>
    <text x="320" y="24" text-anchor="middle" class="dg-zone">BOUNDARY</text>
    <text x="521" y="24" text-anchor="middle" class="dg-zone">WORKER ISOLATES</text>
    <text x="828" y="24" text-anchor="middle" class="dg-zone">NATIVE</text>

    <line x1="290" y1="34" x2="290" y2="388" class="dg-wall"/>
    <line x1="350" y1="34" x2="350" y2="388" class="dg-wall"/>

    <rect x="24" y="40" width="230" height="150" class="dg-box"/>
    <text x="139" y="68" text-anchor="middle" class="dg-flow">Database</text>
    <text x="139" y="96" text-anchor="middle" class="dg-cost">select() · selectBytes()</text>
    <text x="139" y="118" text-anchor="middle" class="dg-cost">execute() · executeBatch()</text>
    <text x="139" y="140" text-anchor="middle" class="dg-cost">transaction()</text>
    <text x="139" y="162" text-anchor="middle" class="dg-cost">stream()</text>

    <rect x="24" y="222" width="230" height="82" class="dg-box"/>
    <text x="139" y="250" text-anchor="middle" class="dg-flow">Stream engine</text>
    <text x="139" y="276" text-anchor="middle" class="dg-cost">dedupe · hash · elide</text>

    <rect x="386" y="40" width="270" height="98" class="dg-box"/>
    <text x="521" y="68" text-anchor="middle" class="dg-flow">Reader pool</text>
    <text x="521" y="94" text-anchor="middle" class="dg-cost">many isolates · parked and reused</text>
    <text x="521" y="116" text-anchor="middle" class="dg-cost">rows decoded here, never on main</text>

    <rect x="386" y="166" width="270" height="120" class="dg-box"/>
    <text x="521" y="194" text-anchor="middle" class="dg-flow">Writer</text>
    <text x="521" y="220" text-anchor="middle" class="dg-cost">one isolate · writes serialized</text>
    <text x="521" y="242" text-anchor="middle" class="dg-cost">binding · batching</text>
    <text x="521" y="264" text-anchor="middle" class="dg-cost">transactions</text>

    <rect x="720" y="40" width="216" height="246" class="dg-box"/>
    <text x="828" y="68" text-anchor="middle" class="dg-flow">SQLite</text>
    <text x="828" y="96" text-anchor="middle" class="dg-cost">multiple ciphers</text>
    <text x="828" y="118" text-anchor="middle" class="dg-cost">WAL journal</text>
    <text x="828" y="156" text-anchor="middle" class="dg-cost">authorizer hook</text>
    <text x="828" y="178" text-anchor="middle" class="dg-cost">pre-update hook</text>
    <text x="828" y="200" text-anchor="middle" class="dg-cost">↳ tell the stream engine</text>
    <text x="828" y="220" text-anchor="middle" class="dg-cost">what actually changed</text>

    <path d="M254,88 L382,88" stroke="var(--accent)" stroke-width="1.6" fill="none" marker-end="url(#ah-acc)"/>
    <text x="320" y="80" text-anchor="middle" class="dg-cost">reads</text>
    <path d="M254,206 L382,206" stroke="var(--accent)" stroke-width="1.6" fill="none" marker-end="url(#ah-acc)"/>
    <text x="320" y="198" text-anchor="middle" class="dg-cost">writes</text>
    <path d="M656,88 L716,88" stroke="var(--ink-2)" stroke-width="1.4" fill="none" marker-end="url(#ah-ink)"/>
    <path d="M656,206 L716,206" stroke="var(--ink-2)" stroke-width="1.4" fill="none" marker-end="url(#ah-ink)"/>

    <path d="M640,340 L258,340" stroke="var(--meas)" stroke-width="1.6" fill="none" marker-end="url(#ah-meas)"/>
    <path d="M640,286 L640,340" stroke="var(--meas)" stroke-width="1.6" fill="none"/>
    <text x="460" y="332" text-anchor="middle" class="dg-cost">finished results and invalidation notices — all main ever receives</text>
  </svg><figcaption>every call crosses the boundary; the main isolate does no SQLite work and no row decoding</figcaption></figure>`,
};
