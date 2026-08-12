// ============================================================
// LETHE — 04_log.scd
// CSV file opening and log functions definition
// Loaded by 03_gan.scd AFTER everything is initialized
// ============================================================

(
var timestamp   = Date.getDate.format("%Y%m%d_%H%M%S");
~logPath        = ~projectPath +/+ "log/lethe_log_%.csv".format(timestamp);
~archivePath    = ~projectPath +/+ "archive/lethe_archive_%.csv".format(timestamp);

// Create log and archive directories if they don't exist
File.mkdir(~projectPath +/+ "log");
File.mkdir(~projectPath +/+ "archive");

~logFile        = File(~logPath, "w");
~archiveFile    = File(~archivePath, "w");

if(~logFile.isOpen.not) {
    "ERROR [LOG] Cannot open lethe_log.csv — check path".postln;
} {
    "[LOG] lethe_log opened: %".format(~logPath).postln;
};

if(~archiveFile.isOpen.not) {
    "ERROR [LOG] Cannot open lethe_archive.csv — check path".postln;
} {
    "[LOG] lethe_archive opened: %".format(~archivePath).postln;
};

// --- HEADER lethe_log.csv ---
~logFile.write(
    "cycle,time_s,phase," ++
    "d_score,d_baseline,d_bias," ++
    "d_w0,d_w1,d_w2,d_w3,d_w4," ++
    "archive_count," ++
    "ef1,ef2,ef3,avg_ef," ++
    "feat0,feat1,feat2,feat3,feat4," ++
    "reward," ++
    "c11,c12,c13,c21,c22,c23,c31,c32,c33," ++
    "del1_time,del2_time,rho," ++
    "base_c11,base_c12,base_c13,base_c21,base_c22,base_c23,base_c31,base_c32,base_c33," ++
    "base_del1,base_del2," ++
    "eps0,eps1,eps2,eps3,eps4,eps5,eps6,eps7,eps8,eps9,eps10," ++
    "amp_circular,amp_fixed,amp_live\n"
);
~logFile.flush;

// --- HEADER lethe_archive.csv ---
~archiveFile.write("snapshot,cycle,slot,feat0,feat1,feat2,feat3,feat4\n");
~archiveFile.flush;

// --- LOG CYCLE FUNCTION ---
// Writes one CSV row per OSC cycle (10 Hz) with full system state
~logCycle = { |ef1, ef2, ef3, features, dScore, reward|
    var timeS    = (Date.getDate.rawSeconds - ~startTime).round(0.01);
    var phase    = if(~isWarmUp) { "warmup" } { "training" };
    var avgEF    = ef1 + ef2 + ef3;
    var rho      = ~computeRho.(~params);
    var dStr     = if(dScore.isNil)  { "" } { dScore.round(0.00001).asString };
    var rStr     = if(reward.isNil)  { "" } { reward.round(0.00001).asString };
    var line;

    line =
        // cycle, time, phase
        "%,%,%,".format(~cycleCount, timeS, phase) ++
        // discriminator
        "%,%,%,".format(dStr, ~dBaseline.round(0.00001), ~dBias.round(0.00001)) ++
        "%,%,%,%,%,".format(
            ~dWeights[0].round(0.00001), ~dWeights[1].round(0.00001),
            ~dWeights[2].round(0.00001), ~dWeights[3].round(0.00001),
            ~dWeights[4].round(0.00001)
        ) ++
        "%,".format(~archiveCount) ++
        // envelopes and features
        "%,%,%,%,".format(
            ef1.round(0.00001), ef2.round(0.00001),
            ef3.round(0.00001), avgEF.round(0.00001)
        ) ++
        "%,%,%,%,%,".format(
            features[0].round(0.00001), features[1].round(0.00001),
            features[2].round(0.00001), features[3].round(0.00001),
            features[4].round(0.00001)
        ) ++
        // reward
        "%,".format(rStr) ++
        // current FDN params
        "%,%,%,%,%,%,%,%,%,".format(
            ~params[\c11].round(0.00001), ~params[\c12].round(0.00001),
            ~params[\c13].round(0.00001), ~params[\c21].round(0.00001),
            ~params[\c22].round(0.00001), ~params[\c23].round(0.00001),
            ~params[\c31].round(0.00001), ~params[\c32].round(0.00001),
            ~params[\c33].round(0.00001)
        ) ++
        "%,%,%,".format(
            ~params[\del1_time].round(0.00001),
            ~params[\del2_time].round(0.00001),
            rho.round(0.00001)
        ) ++
        // NES baseParams
        "%,%,%,%,%,%,%,%,%,".format(
            ~baseParams[\c11].round(0.00001), ~baseParams[\c12].round(0.00001),
            ~baseParams[\c13].round(0.00001), ~baseParams[\c21].round(0.00001),
            ~baseParams[\c22].round(0.00001), ~baseParams[\c23].round(0.00001),
            ~baseParams[\c31].round(0.00001), ~baseParams[\c32].round(0.00001),
            ~baseParams[\c33].round(0.00001)
        ) ++
        "%,%,".format(
            ~baseParams[\del1_time].round(0.00001),
            ~baseParams[\del2_time].round(0.00001)
        ) ++
        // NES perturbation
        "%,%,%,%,%,%,%,%,%,%,%,".format(
            ~currentPerturb[0].round(0.00001), ~currentPerturb[1].round(0.00001),
            ~currentPerturb[2].round(0.00001), ~currentPerturb[3].round(0.00001),
            ~currentPerturb[4].round(0.00001), ~currentPerturb[5].round(0.00001),
            ~currentPerturb[6].round(0.00001), ~currentPerturb[7].round(0.00001),
            ~currentPerturb[8].round(0.00001), ~currentPerturb[9].round(0.00001),
            ~currentPerturb[10].round(0.00001)
        ) ++
        // mixer
        "%,%,%".format(~ampCircular, ~ampFixed, ~ampLive);

    ~logFile.write(line ++ "\n");
    ~logFile.flush;
};

// --- LOG ARCHIVE FUNCTION ---
// Writes a full snapshot of all slots (including empty/zero ones)
// every time the archive changes. In Python: heatmap snapshot x slot.
~snapshotCount = 0;
~logArchive = { |features|
    // Writes all archiveSize slots — zeros included
    ~archiveSize.do({ |slot|
        var f = ~archive[slot];
        var line = "%,%,%,%,%,%,%,%".format(
            ~snapshotCount, ~cycleCount, slot,
            f[0].round(0.00001), f[1].round(0.00001),
            f[2].round(0.00001), f[3].round(0.00001),
            f[4].round(0.00001)
        );
        ~archiveFile.write(line ++ "\n");
    });
    ~archiveFile.flush;
    ~snapshotCount = ~snapshotCount + 1;
};

// Clean shutdown on server quit
ServerQuit.add({
    ~logFile.close;
    ~archiveFile.close;
    "[LOG] CSV files closed.".postln;
});

"[LOG] Logger ready".postln;
)