// ============================================================
// LETHE — 02_synth.scd
// FDN SynthDef, buffer management, recording startup
// ============================================================
// FDN convention (standard): c_ij = contribution of input j to output i.
// Inputs (columns): gen_in, del1_fb, del2_fb
// Outputs (rows): out1, out2, out3
// ============================================================

(
var sampleRate = s.sampleRate.asInteger;

// --- SYNTHDEFS ---

SynthDef(\lethe_fdn, {
    arg out = 0, bufnum = 0, frozenbufnum = 0,
        masterAmp = 1.0, lagTime = 2.0,
        ef_attack = 0.01, ef_release = 1.0,
        // Standard FDN convention: c_ij = input j → output i
        c11 = 0.5, c12 = 0.2, c13 = 0.1,   // out1 row
        c21 = 0.4, c22 = 0.6, c23 = 0.1,   // out2 row
        c31 = 0.3, c32 = 0.1, c33 = 0.6,   // out3 row
        del1_time = 0.5, del2_time = 0.5,
        feedbackGBuffer = 0.9,
        // Source mixer — summed, range [0.0-1.0] each.
        ampCircular = 1.0,   // circular buffer (rewritten)
        ampFixed    = 0.0,   // frozen buffer (original intact)
        ampLive     = 0.0,   // direct mic/interface input
        liveIn      = 0;     // hardware channel for live mode

    var gen_in, del1_fb, del2_fb;
    var out1, out2, out3, del1_out, del2_out;
    var ef1, ef2, ef3, totalOut, monoOut;
    var srcCircular, srcFixed, srcLive;

    var c11_s = VarLag.kr(c11, lagTime), c12_s = VarLag.kr(c12, lagTime), c13_s = VarLag.kr(c13, lagTime);
    var c21_s = VarLag.kr(c21, lagTime), c22_s = VarLag.kr(c22, lagTime), c23_s = VarLag.kr(c23, lagTime);
    var c31_s = VarLag.kr(c31, lagTime), c32_s = VarLag.kr(c32, lagTime), c33_s = VarLag.kr(c33, lagTime);

    # del1_fb, del2_fb = LocalIn.ar(2, 0.0);

    // The three sources — each with its own amplitude and smooth crossfade.
    srcCircular = PlayBuf.ar(1, bufnum,       loop: 1) * ampCircular.lag(1.0);
    srcFixed    = PlayBuf.ar(1, frozenbufnum, loop: 1) * ampFixed.lag(1.0);
    srcLive     = SoundIn.ar(liveIn)                   * ampLive.lag(1.0);

    // gen_in is the sum of the three sources — FDN input.
    gen_in = srcCircular + srcFixed + srcLive;

    // Standard FDN: out_i = sum_j c_ij * input_j
    out1 = (c11_s * gen_in) + (c12_s * del1_fb) + (c13_s * del2_fb);
    out2 = (c21_s * gen_in) + (c22_s * del1_fb) + (c23_s * del2_fb);
    out3 = (c31_s * gen_in) + (c32_s * del1_fb) + (c33_s * del2_fb);

    del1_out = DelayL.ar(out2, 4.0, VarLag.kr(del1_time, lagTime));
    del2_out = DelayL.ar(out3, 4.0, VarLag.kr(del2_time, lagTime));

    LocalOut.ar([del1_out, del2_out]);

    ef1 = EnvFollow.ar(out1.abs,     ef_attack, ef_release);
    ef2 = EnvFollow.ar(del1_out.abs, ef_attack, ef_release);
    ef3 = EnvFollow.ar(del2_out.abs, ef_attack, ef_release);

    SendReply.kr(Impulse.kr(10), '/lethe_env', [ef1, ef2, ef3]);

    Out.ar(0, (out1 + del1_out) * masterAmp.lag(0.5));
    Out.ar(1, (out1 + del2_out) * masterAmp.lag(0.5));

    // RecordBuf always writes to genBuf (bufnum) regardless of mode —
    // only circular reads it back, but writing always happens so the
    // buffer is ready if you switch modes.
    totalOut = out1 + del1_out + del2_out;
    monoOut  = totalOut * feedbackGBuffer;
    RecordBuf.ar(LeakDC.ar(monoOut), bufnum, loop: 1, recLevel: 1.0, trigger: 1);

}).add;

SynthDef(\lethe_input_rec, {
    arg bufnum = 0, in = 0;
    //RecordBuf.ar(WhiteNoise.ar(0.5), bufnum, loop: 0, doneAction: 2);
    //RecordBuf.ar(Impulse.ar(2, 0, 0.8), bufnum, loop: 0, doneAction: 2);
    //RecordBuf.ar(PinkNoise.ar(0.5), bufnum, loop: 0, doneAction: 2);
    //RecordBuf.ar(Pulse.ar(110, 0.5, 0.5), bufnum, loop: 0, doneAction: 2);
    RecordBuf.ar(Saw.ar(110) * 0.5 , bufnum, loop: 0, doneAction: 2);
    //RecordBuf.ar(SoundIn.ar(in), bufnum, loop: 0, doneAction: 2);
}).add;

s.sync;

// --- SYSTEM STARTUP BASED ON inputMode ---

switch(~inputMode,

    \mic, {
        // Mic mode: record for ~bufDur seconds then start
        var bufSize = (sampleRate * ~bufDur).asInteger;
        ~genBuf    = Buffer.alloc(s, bufSize, 1);
        ~frozenBuf = Buffer.alloc(s, bufSize, 1);
        // warmUp = one full buffer cycle
        ~warmUpCycles = (~bufDur * 10).asInteger;

        "============================================".postln;
        "LETHE — MIC mode".postln;
        "Recording: % seconds — make some noise!".format(~bufDur).postln;
        "Auto warm-up: % cycles (% s)".format(~warmUpCycles, ~bufDur).postln;
        "============================================".postln;

        ~inputRec = Synth(\lethe_input_rec, [\bufnum, ~genBuf, \in, ~liveIn]);

        {
            ~bufDur.wait;
            // Freeze the original buffer before FDN starts rewriting it
            ~genBuf.copyData(~frozenBuf);
            "LETHE [MIC] Buffer ready — starting FDN and GAN...".postln;
            (~projectPath +/+ "03_gan.scd").load;
        }.fork;
    },

    \file, {
        // File mode: load audio file from project folder
        var filePath = ~projectPath +/+ ~audioFile;
        "LETHE — FILE mode: %".format(filePath).postln;

        // Load file converting to mono (channel 0)
        ~genBuf = Buffer.readChannel(s, filePath, channels: [0], action: { |buf|
            ~bufDur     = buf.duration;
            ~frozenBuf  = Buffer.alloc(s, buf.numFrames, 1);
            // warmUp = one full file cycle
            ~warmUpCycles = (~bufDur * 10).asInteger;

            buf.copyData(~frozenBuf);

            "============================================".postln;
            "LETHE — file loaded: %".format(~audioFile).postln;
            "Duration: % s — Warm-up: % cycles".format(~bufDur.round(0.01), ~warmUpCycles).postln;
            "============================================".postln;

            (~projectPath +/+ "03_gan.scd").load;
        });
    },

    \live, {
        // Live mode: no buffer, direct input
        // genBuf and frozenBuf allocated small as placeholders
        // (PlayBuf not used in pure live mode but SynthDef requires it)
        ~genBuf    = Buffer.alloc(s, sampleRate, 1);
        ~frozenBuf = Buffer.alloc(s, sampleRate, 1);
        // manual warmUp from config
        "============================================".postln;
        "LETHE — LIVE mode".postln;
        "Manual warm-up: % cycles (% s)".format(~warmUpCycles, (~warmUpCycles / 10.0).round(0.1)).postln;
        "============================================".postln;

        (~projectPath +/+ "03_gan.scd").load;
    }
);

"[SYNTH] SynthDefs loaded".postln;
)