// ============================================================
// LETHE — 01_config.scd
// User parameters — edit here before running
// ============================================================
// FDN convention (standard): c_ij = contribution of input j to output i.
// Inputs (columns): gen_in, del1_fb, del2_fb
// Outputs (rows): out1, out2, out3
// Matrix:  out1 = c11*gen_in + c12*del1_fb + c13*del2_fb
//          out2 = c21*gen_in + c22*del1_fb + c23*del2_fb
//          out3 = c31*gen_in + c32*del1_fb + c33*del2_fb
// ============================================================

// --- INPUT MODE ---
// \mic = record from mic for ~bufDur s | \file = load audio file | \live = direct mic input
~inputMode = \mic;

// Audio file to load (only for ~inputMode = \file). Must be in project folder. wav/aiff/flac, auto-mono.
~audioFile = "PAROLAI.WAV";

// --- BUFFER ---
// Recording duration in seconds (only for ~inputMode = \mic). Ignored in \live mode.
~bufDur = 10.0;

// --- DELAY ---
// FDN delay lines explored by G within this range [s]. Narrow = fast, wide = slow.
~delayTimeMin = 0.001;
~delayTimeMax = 0.1;

// --- FEEDBACK BUFFER ---
// How much FDN output is rewritten into the circular buffer each cycle. Main life/death control.
~feedbackGBuffer = 0.75;

// --- ENVELOPE FOLLOWER ---
// Three meters measuring amplitude at out1, del1_out, del2_out.
~ef_attack  = 0.01;   // Attack time [s] — fast = transients, slow = smooth
~ef_release = 1.0;    // Release time [s] — fast = forgets quickly, slow = holds memory

// --- GAN — DISCRIMINATOR ---

// OSC cycles (at 10Hz) D listens to FDN with initial params to build DNA. Auto-computed in \mic/\file.
~warmUpCycles = 50;

// How many sound snapshots the archive can hold. Larger = richer DNA, smaller = focused DNA.
~archiveSize = 100;

// Min D-score to update archive with current sound. High = strict, low = archive updates easily.
~archiveThreshold = 0.55;

// Discriminator learning rate. High = fast but unstable, low = slow but stable.
~dLR = 0.005;

// Adaptive feature normalization update speed. High = short window, low = long window.
~featAlpha = 0.02;

// --- GAN — GENERATOR ---

// How many OSC cycles between G updates of FDN params. At 10Hz: 10=1s, 30=3s, 100=10s.
~gUpdateEvery = 10;

// Generator learning rate (perturbation step size). High = bold changes, low = cautious changes.
~gLR = 0.5;

// --- INITIAL FDN PARAMS (standard convention: c_ij = input j → output i) ---
// Row 1 (out1): c11=input routing, c12=del1→out1, c13=del2→out1
// Row 2 (out2): c21=input routing, c22=self-feedback del1, c23=cross del2→del1
// Row 3 (out3): c31=input routing, c32=cross del1→del2, c33=self-feedback del2
// del_time: initial delay position in normalized [0,1] → mapped to [delayTimeMin, delayTimeMax]
~initParams = (
    c11: 0.5,  c12: 0.2,  c13: 0.2,
    c21: 0.5,  c22: 0.6,  c23: 0.1,
    c31: 0.5,  c32: 0.2,  c33: 0.6,
    del1_time: 0.5,
    del2_time: 0.5
);

// --- G SIGMA — perturbation scale per parameter (standard convention) ---
// Each param updated via random perturbation scaled by these values.
// Hierarchy reflects physical danger: c22/c33 have large sigma + positive bias.
~initSigmas = [
    0.05,   // c11 — nearly harmless (input → out1)
    0.08,   // c12 — del1 to direct out
    0.08,   // c13 — del2 to direct out
    0.05,   // c21 — signal into delay 1 (input → out2)
    0.20,   // c22 ★★ self-feedback del1 — positive bias
    0.12,   // c23 — cross del2→del1
    0.05,   // c31 — signal into delay 2 (input → out3)
    0.12,   // c32 — cross del1→del2
    0.20,   // c33 ★★ self-feedback del2 — positive bias
    0.15,   // del1_time — normalized [0,1]
    0.15    // del2_time — normalized [0,1]
];

// --- COUPLING ---
// When G updates a param, coupling propagates the change to others via physical hierarchy.

// Anti-coupling c22↔c33: when one rises, the other falls. Creates asymmetry between delays.
~coupAC = 0.4;

// Co-coupling c32↔c23: both sides of cross-loop move together. Keeps loop balanced.
~coupCC = 0.6;

// Follow c21/c31 on c22/c33: input routing (c21/c31) weakly adapts to dominant delay.
~coupFF = 0.25;

// --- SOURCE MIXER ---
// Three channels summed — use alone or combined. All zero except one = pure mode.
// circular: FDN rewrites buffer each cycle (aggressive transform).
// fixed:    original recorded buffer never touched (stable transform, DNA intact).
// live:     direct mic/interface input, no buffer (real-time processing).
~ampCircular = 1.0;
~ampFixed    = 0.0;
~ampLive     = 0.0;

// Hardware input channel for live source (0 = first input).
~liveIn = 0;

// ============================================================
// LIVE CONTROLS (from post window while running):
//   ~gUpdateEvery / ~coupAC / ~coupCC / ~coupFF
//   ~delayTimeMin / ~delayTimeMax
//   ~fdnSynth.set(\masterAmp, x)
//   ~fdnSynth.set(\lagTime, x)
//   ~fdnSynth.set(\feedbackGBuffer, x)
//   ~fdnSynth.set(\ef_attack, x) / ~fdnSynth.set(\ef_release, x)
//   ~fdnSynth.set(\ampCircular, x) → circular buffer mix [0.0-1.0]
//   ~fdnSynth.set(\ampFixed, x)    → frozen buffer mix [0.0-1.0]
//   ~fdnSynth.set(\ampLive, x)     → live input mix [0.0-1.0]
// To stop: s.freeAll
// ============================================================

"[CONFIG] Parameters loaded — inputMode: %".format(~inputMode).postln;