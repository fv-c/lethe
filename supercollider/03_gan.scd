// ============================================================
// LETHE — 03_gan.scd
// Discriminator, NES Generator, coupling, OSCdef
// ============================================================
// FDN convention (standard): c_ij = contribution of input j to output i.
// Inputs (columns): gen_in, del1_fb, del2_fb
// Outputs (rows): out1, out2, out3
// ============================================================

(
// --- GAN STATE ---
~isWarmUp      = true;
~baseParams    = ~initParams.copy;
~params        = ~baseParams.copy;
~gParamSigmas  = ~initSigmas.copy;
~startTime     = Date.getDate.rawSeconds;

// Standard FDN order: c11,c12,c13,c21,c22,c23,c31,c32,c33,del1_time,del2_time
~gParamKeys  = [\c11,\c12,\c13,\c21,\c22,\c23,\c31,\c32,\c33,\del1_time,\del2_time];
~gParamClips = [
    [-1.0, 1.0], [-1.0, 1.0], [-1.0, 1.0],   // c11, c12, c13 (out1 row)
    [-1.0, 1.0], [-0.99, 0.99], [-1.0, 1.0],  // c21, c22, c23 (out2 row)
    [-1.0, 1.0], [-1.0, 1.0],  [-0.99, 0.99],  // c31, c32, c33 (out3 row)
    nil, nil                                    // del1_time, del2_time
];

// --- SPECTRAL RADIUS ---
// Stability depends on the 2x2 feedback submatrix (rows 2,3 × cols 2,3):
//   [c22 c23]
//   [c32 c33]
~computeRho = { |p|
    var a = p[\c22]; var b = p[\c23];
    var c = p[\c32]; var d = p[\c33];
    var tr = a + d;
    var dt = (a * d) - (b * c);
    var disc = (tr * tr) - (4.0 * dt);
    if(disc >= 0.0) {
        ((tr + disc.sqrt) * 0.5).abs.max(((tr - disc.sqrt) * 0.5).abs)
    } {
        dt.abs.sqrt
    }
};

~enforceSpectral = { |p|
    var rho = ~computeRho.(p);
    if(rho > 0.99) {
        // First: scale cross-feedback terms
        p[\c23] = p[\c23] * 0.9;
        p[\c32] = p[\c32] * 0.9;
        rho = ~computeRho.(p);
        if(rho > 0.99) {
            // Second: scale entire feedback block
            var scale2 = 0.99 / rho;
            p[\c22] = p[\c22] * scale2;
            p[\c23] = p[\c23] * scale2;
            p[\c32] = p[\c32] * scale2;
            p[\c33] = p[\c33] * scale2;
        };
    };
};

// --- HIERARCHICAL COUPLING ---
// Standard convention: c21/c31 = input routing, c22/c33 = self-feedback
~applyCoupling = { |p, oldP|
    var dc22 = p[\c22] - oldP[\c22];
    var dc33 = p[\c33] - oldP[\c33];
    var dc32 = p[\c32] - oldP[\c32];
    var dc23 = p[\c23] - oldP[\c23];
    // Anti-correlation: self-feedback c22↔c33
    p[\c33] = (p[\c33] - (~coupAC * dc22)).clip(-0.99, 0.99);
    p[\c22] = (p[\c22] - (~coupAC * dc33)).clip(-0.99, 0.99);
    // Co-correlation: cross-feedback c32↔c23
    p[\c23] = (p[\c23] + (~coupCC * dc32)).clip(-1.0, 1.0);
    p[\c32] = (p[\c32] + (~coupCC * dc23)).clip(-1.0, 1.0);
    // Follow: input routing (c21/c31) adapts to dominant self-feedback
    p[\c21] = (p[\c21] + (~coupFF * dc22)).clip(-1.0, 1.0);
    p[\c31] = (p[\c31] + (~coupFF * dc33)).clip(-1.0, 1.0);
};

// --- CIRCULAR MEMORY ---
~memSize    = 128;
~memory     = Array.fill(~memSize, { [0.0, 0.0, 0.0] });
~memPtr     = 0;
~cycleCount = 0;

~writeMemory = { |ef_vec|
    ~memory[~memPtr] = ef_vec;
    ~memPtr = (~memPtr + 1) % ~memSize;
};

// --- DISCRIMINATOR ---
~nFeatures = 5;
~dWeights  = Array.fill(~nFeatures, { rrand(-0.1, 0.1) });
~dBias     = 0.0;
~featMean  = Array.fill(~nFeatures, { 0.0 });
~featVar   = Array.fill(~nFeatures, { 1.0 });

~sigmoid = { |x| 1.0 / (1.0 + exp(x.neg.clip(-20.0, 20.0))) };

~computeFeatures = { |ef1, ef2, ef3|
    var avgEF      = ef1 + ef2 + ef3;
    var recentMean = ~memory.collect({ |v| v[0] + v[1] + v[2] }).sum / ~memSize;
    var ef1_norm   = ef1 / avgEF.max(0.001);
    var ef2_norm   = ef2 / avgEF.max(0.001);
    var ef3_norm   = ef3 / avgEF.max(0.001);
    var trend_norm = (avgEF - recentMean) / recentMean.max(0.001);
    var raw        = [ef1_norm, ef2_norm, ef3_norm, avgEF, trend_norm];
    raw.do({ |x, i|
        var diff = x - ~featMean[i];
        ~featMean[i] = ~featMean[i] + (~featAlpha * diff);
        ~featVar[i]  = ((~featVar[i] * (1.0 - ~featAlpha)) + (~featAlpha * (diff * diff))).max(1e-6);
    });
    raw.collect({ |x, i|
        ((x - ~featMean[i]) / (~featVar[i].sqrt)).clip(-3.0, 3.0)
    })
};

~dForward = { |features|
    var logit = features.collect({ |f, i| f * ~dWeights[i] }).sum + ~dBias;
    ~sigmoid.(logit)
};

// --- ARCHIVE (DNA) ---
~archive      = Array.fill(~archiveSize, { Array.fill(~nFeatures, { 0.0 }) });
~archivePtr   = 0;
~archiveCount = 0;

~archiveAdd = { |features|
    ~archive[~archivePtr] = features;
    ~archivePtr   = (~archivePtr + 1) % ~archiveSize;
    ~archiveCount = (~archiveCount + 1).min(~archiveSize);
    ~logArchive.(features);
};

~archiveSample = {
    if(~archiveCount > 0) {
        ~archive[~archiveCount.min(~archiveSize - 1).rand]
    } {
        Array.fill(~nFeatures, { 0.0 })
    }
};

// --- DISCRIMINATOR TRAINING ---
~dTrain = { |fakeFeatures, dFakeScore|
    if(~archiveCount >= 8) {
        var realFeatures = ~archiveSample.();
        var dRealScore   = ~dForward.(realFeatures);
        var gradW = Array.fill(~nFeatures, { |i|
            (fakeFeatures[i] * dFakeScore) - (realFeatures[i] * (1.0 - dRealScore))
        });
        var gradB = dFakeScore - (1.0 - dRealScore);
        ~dWeights = ~dWeights.collect({ |w, i|
            (w - (~dLR * gradW[i])).clip(-8.0, 8.0)
        });
        ~dBias = (~dBias - (~dLR * gradB)).clip(-8.0, 8.0);
    };
};

// --- GENERATOR (single-sample perturbation update) ---
~dAccum         = 0.0;
~dBaseline      = 0.5;
~baseAlpha      = 0.01;
~currentPerturb = Array.fill(11, { 0.0 });
~lastReward     = 0.0;

~applyPerturb = {
    ~gParamKeys.do({ |key, i|
        if(i < 9) {
            ~params[key] = (~baseParams[key] + ~currentPerturb[i])
                .clip(~gParamClips[i][0], ~gParamClips[i][1]);
        };
    });
    ~params[\del1_time] = (~baseParams[\del1_time] + ~currentPerturb[9])
        .clip(0.0, 1.0).linlin(0.0, 1.0, ~delayTimeMin, ~delayTimeMax);
    ~params[\del2_time] = (~baseParams[\del2_time] + ~currentPerturb[10])
        .clip(0.0, 1.0).linlin(0.0, 1.0, ~delayTimeMin, ~delayTimeMax);
    ~enforceSpectral.(~params);
};

~sampleNewPerturb = {
    ~currentPerturb = ~gParamSigmas.collect({ |sig, i|
        // c22 (index 4) and c33 (index 8): positive bias
        if(i == 4 || i == 8) {
            rrand(-0.3, 1.0) * sig
        } {
            rrand(-1.0, 1.0) * sig
        }
    });
    ~applyPerturb.();
};

~gTrain = { |meanDScore|
    var reward  = meanDScore - ~dBaseline;
    var oldBase = ~baseParams.copy;
    ~lastReward = reward;
    ~gParamKeys.do({ |key, i|
        var update = (~gLR * ~currentPerturb[i]) * reward;
        if(i < 9) {
            ~baseParams[key] = (~baseParams[key] + update)
                .clip(~gParamClips[i][0], ~gParamClips[i][1]);
        } {
            ~baseParams[key] = (~baseParams[key] + update).clip(0.0, 1.0);
        };
    });
    ~applyCoupling.(~baseParams, oldBase);
    ~enforceSpectral.(~baseParams);
    ~dBaseline = (~dBaseline * (1.0 - ~baseAlpha)) + (meanDScore * ~baseAlpha);
    ~sampleNewPerturb.();
};

~sampleNewPerturb.();

// --- LOAD LOGGER now that everything is initialized ---
(~projectPath +/+ "04_log.scd").load; // comment out this line to disable logging

// --- OSCDEF — main loop at 10Hz ---
OSCdef(\lethe_listener, { |msg|
    var ef1, ef2, ef3, features, dScore, avgEF, rho;
    ef1   = msg[3]; ef2 = msg[4]; ef3 = msg[5];
    avgEF = ef1 + ef2 + ef3;
    rho   = ~computeRho.(~params);
    ~writeMemory.([ef1, ef2, ef3]);
    ~cycleCount = ~cycleCount + 1;
    features = ~computeFeatures.(ef1, ef2, ef3);

    if(~isWarmUp) {
        ~archiveAdd.(features);
        ~logCycle.(ef1, ef2, ef3, features, nil, nil);

        if(~cycleCount % 10 == 0) {
            "LETHE [WARMUP] % / % | arch:%".format(
                ~cycleCount, ~warmUpCycles, ~archiveCount
            ).postln;
        };

        if(~cycleCount >= ~warmUpCycles) {
            ~isWarmUp = false;
            "============================================".postln;
            "LETHE [WARMUP] complete — arch:%".format(~archiveCount).postln;
            "LETHE [TRAINING] started".postln;
            "============================================".postln;
        };

    } {
        dScore  = ~dForward.(features);
        ~dAccum = ~dAccum + dScore;
        ~dTrain.(features, dScore);
        if(dScore > ~archiveThreshold) { ~archiveAdd.(features) };

        if(~cycleCount % ~gUpdateEvery == 0) {
            ~gTrain.(~dAccum / ~gUpdateEvery);
            ~logCycle.(ef1, ef2, ef3, features, dScore, ~lastReward);
            ~dAccum = 0.0;

            // Console log — FDN + essential GAN
            "LETHE [G] #% | r:% | D:%".format(
                ~cycleCount,
                ~lastReward.round(0.0001),
                ~dBaseline.round(0.0001)
            ).postln;
            "  FDN | c11:% c12:% c13:%".format(
                ~params[\c11].round(0.001), ~params[\c12].round(0.001), ~params[\c13].round(0.001)
            ).postln;
            "       c21:% c22:% c23:%".format(
                ~params[\c21].round(0.001), ~params[\c22].round(0.001), ~params[\c23].round(0.001)
            ).postln;
            "       c31:% c32:% c33:%".format(
                ~params[\c31].round(0.001), ~params[\c32].round(0.001), ~params[\c33].round(0.001)
            ).postln;
            "       d1:% d2:% ρ:%".format(
                ~params[\del1_time].round(0.001), ~params[\del2_time].round(0.001),
                rho.round(0.001)
            ).postln;

        } {
            ~logCycle.(ef1, ef2, ef3, features, dScore, nil);
        };

        // Light console log every 20 cycles
        if(~cycleCount % 20 == 0) {
            "LETHE [D] #% | score:% | arch:%".format(
                ~cycleCount, dScore.round(0.001), ~archiveCount
            ).postln;
        };

        ~fdnSynth.set(
            \c11,~params[\c11],\c12,~params[\c12],\c13,~params[\c13],
            \c21,~params[\c21],\c22,~params[\c22],\c23,~params[\c23],
            \c31,~params[\c31],\c32,~params[\c32],\c33,~params[\c33],
            \del1_time,~params[\del1_time],\del2_time,~params[\del2_time]
        );
    };
}, '/lethe_env');

// --- START FDN SYNTH ---
~fdnSynth = Synth(\lethe_fdn, [
    \out, 0, \bufnum, ~genBuf, \frozenbufnum, ~frozenBuf,
    \masterAmp, 1.0, \lagTime, 2.0,
    \ef_attack, ~ef_attack, \ef_release, ~ef_release,
    \feedbackGBuffer, ~feedbackGBuffer,
    \ampCircular, ~ampCircular,
    \ampFixed,    ~ampFixed,
    \ampLive,     ~ampLive,
    \liveIn,      ~liveIn,
    \c11,~params[\c11],\c12,~params[\c12],\c13,~params[\c13],
    \c21,~params[\c21],\c22,~params[\c22],\c23,~params[\c23],
    \c31,~params[\c31],\c32,~params[\c32],\c33,~params[\c33],
    \del1_time,~params[\del1_time],\del2_time,~params[\del2_time]
]);

"============================================".postln;
"LETHE - Latent-parameter Evolution with Temporal Hierarchical quasi-Equilibrium".postln;
"============================================".postln;
"SOURCE MIXER:".postln;
"  ~fdnSynth.set(\\ampCircular, x) → circular buffer [0.0-1.0]".postln;
"  ~fdnSynth.set(\\ampFixed, x)    → frozen buffer [0.0-1.0]".postln;
"  ~fdnSynth.set(\\ampLive, x)     → live input    [0.0-1.0]".postln;
"============================================".postln;
)