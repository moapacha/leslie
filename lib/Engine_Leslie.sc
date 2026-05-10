// Engine_Leslie
// rotating speaker emulation for monome norns
// dual-rotor: horn (high) + bass drum (low) with independent LFOs
// each rotor: doppler (modulated delay) + AM (tremolo) + pan
// LR4 crossover, smooth spin-up / spin-down via Lag

Engine_Leslie : CroneEngine {
    var <synth;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        SynthDef(\leslie, {
            arg out=0,
                hornRate=6.8, bassRate=5.6,
                hornAccel=0.5, bassAccel=1.2,
                hornDopp=0.0012, bassDopp=0.0022,
                hornAm=0.5, bassAm=0.4,
                width=1.0, mix=1.0, drive=1.0,
                xfreq=800, brake=0;

            var dry, in, sig, bass, horn;
            var hornLfo, bassLfo, hornCur, bassCur, brakeAmt;

            // sum stereo input to mono, soft saturate when driven
            dry = SoundIn.ar([0, 1]);
            in = (dry[0] + dry[1]) * 0.5;
            in = (in * drive).tanh;

            // smoothed rate (spin-up/down) and brake
            brakeAmt = Lag.kr(brake, 0.4);
            hornCur = Lag.kr(hornRate, hornAccel) * (1 - brakeAmt);
            bassCur = Lag.kr(bassRate, bassAccel) * (1 - brakeAmt);

            // counter-rotating LFOs (bass spins opposite for natural beating)
            hornLfo = SinOsc.kr(hornCur);
            bassLfo = SinOsc.kr(bassCur.neg);

            // 4th order Linkwitz-Riley crossover (sums flat in magnitude)
            bass = LPF.ar(LPF.ar(in, xfreq), xfreq);
            horn = HPF.ar(HPF.ar(in, xfreq), xfreq);

            // doppler: vary delay around a safe center so that
            // (center - max_dopp) stays well above zero
            horn = DelayC.ar(horn, 0.05, (hornLfo * hornDopp) + 0.012);
            bass = DelayC.ar(bass, 0.05, (bassLfo * bassDopp) + 0.015);

            // tremolo: amplitude oscillates around (1 - depth/2)
            horn = horn * ((1 - (hornAm * 0.5)) + (hornLfo * hornAm * 0.5));
            bass = bass * ((1 - (bassAm * 0.5)) + (bassLfo * bassAm * 0.5));

            // stereo pan: each rotor pans with its own LFO. since bassLfo
            // already counter-rotates, the two bands sweep at different
            // rates in opposite directions, which is what gives Leslie
            // its characteristic wide, swirling image.
            horn = Pan2.ar(horn, hornLfo * width);
            bass = Pan2.ar(bass, bassLfo * width);

            // wet + dry mix
            sig = (horn + bass);
            sig = (sig * mix) + (dry * (1 - mix));

            Out.ar(out, sig);
        }).add;

        context.server.sync;

        synth = Synth.new(\leslie, [
            \out, context.out_b.index
        ], context.xg);

        this.addCommand("hornRate",  "f", { arg msg; synth.set(\hornRate,  msg[1]); });
        this.addCommand("bassRate",  "f", { arg msg; synth.set(\bassRate,  msg[1]); });
        this.addCommand("hornAccel", "f", { arg msg; synth.set(\hornAccel, msg[1]); });
        this.addCommand("bassAccel", "f", { arg msg; synth.set(\bassAccel, msg[1]); });
        this.addCommand("hornDopp",  "f", { arg msg; synth.set(\hornDopp,  msg[1]); });
        this.addCommand("bassDopp",  "f", { arg msg; synth.set(\bassDopp,  msg[1]); });
        this.addCommand("hornAm",    "f", { arg msg; synth.set(\hornAm,    msg[1]); });
        this.addCommand("bassAm",    "f", { arg msg; synth.set(\bassAm,    msg[1]); });
        this.addCommand("width",     "f", { arg msg; synth.set(\width,     msg[1]); });
        this.addCommand("mix",       "f", { arg msg; synth.set(\mix,       msg[1]); });
        this.addCommand("drive",     "f", { arg msg; synth.set(\drive,     msg[1]); });
        this.addCommand("xfreq",     "f", { arg msg; synth.set(\xfreq,     msg[1]); });
        this.addCommand("brake",     "f", { arg msg; synth.set(\brake,     msg[1]); });
    }

    free {
        synth.free;
    }
}
