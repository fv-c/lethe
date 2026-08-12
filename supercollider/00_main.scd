// ============================================================
// LETHE — SELF-REFERENTIAL GAN
// LETHE - Latent-parameter Evolution with Temporal Hierarchical quasi-Equilibrium
// ============================================================
// FILE: 00_main.scd
// Entry point — loads all other files in order.
// Run ONLY this file with Ctrl+A then Ctrl+Enter.
// ============================================================


//PATH
~projectPath = thisProcess.nowExecutingPath.dirname;

// RUN
(
s.waitForBoot({

    "============================================".postln;
    "LETHE — starting system...".postln;
    "Project folder: %".format(~projectPath).postln;
    "============================================".postln;

    // 1. User parameters
    (~projectPath +/+ "01_config.scd").load;
    s.sync;

    // 2. Synth — buffers, SynthDef, start recording
    //    At the end it loads 03_gan.scd which in turn loads 04_log.scd
    (~projectPath +/+ "02_synth.scd").load;

});
)


// RECORDING
(
var timestamp   = Date.getDate.format("%Y%m%d_%H%M%S");
s.record(~projectPath +/+ "rec/lethe_audio_%.wav".format(timestamp));
)

// stop recording
s.stopRecording



