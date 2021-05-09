/*

ORBIT BASED (GLOBAL)
CORE SYNTHDEFS FOR DIRT
(REQUIRED: GlobalDirtEffects)

	Global synth defs: these synths run in each DirtOrbit and are only released when it is stopped
	when you change them, to update them, hit cmd-period (i.e. stop the synths on the server) once.
	they'll come back automatically

*/



(
{
	var numChannels = ~dirt.numChannels;
	var arenaBuffer = Buffer.alloc(~dirt.server, ~dirt.server.sampleRate, numChannels);
	var offsetDict = Dictionary.newFrom([\delay, 0, \room, 1, \leslie, 2, \hall, 3, \tape, 4, \arena, 5]);

	arenaBuffer.sine3(Array.exprand(100,20,8000), Array.rand(100,0,1), Array.rand(100,-1,1));

	/*

	Routing and Analysis

	*/

	SynthDef("dirt_monitor" ++ numChannels, { |dryBus, effectBus, outBus, gate = 1, limitertype = 1|
		var drySignal = In.ar(dryBus, numChannels);
		var wetSignal = In.ar(effectBus, numChannels);
		//var signal = XFade2.ar(wetSignal, drySignal, dry * 2 - 1);
		var signal = wetSignal + drySignal;
		var post = if(SuperDirt.postBadValues) { 2 } { 0 };

		signal = Select.ar(CheckBadValues.ar(signal, post: post) > 0, [signal, DC.ar(0)]);

		signal = Select.ar(limitertype,
			[
				signal,
				Limiter.ar(signal),
				softclip(signal * 0.5) * 2
			]
		);

		DirtPause.ar(signal, graceTime:4);

		signal = signal * EnvGen.kr(Env.asr, gate, doneAction:2);
		Out.ar(outBus, signal)
	}, [\ir, \ir, \kr, \kr, \kr]).add;


	// RMS measurement, sending back to editor
	SynthDef("dirt_rms" ++ numChannels, { |gate = 1, dryBus, effectBus, rmsReplyRate, rmsPeakLag, orbitIndex|
		var drySignal = In.ar(dryBus, numChannels);
		var wetSignal = In.ar(effectBus, numChannels);
		var signal = wetSignal + drySignal;

		DirtPause.ar(signal, graceTime:4);
		EnvGen.kr(Env.asr, gate, doneAction:2);

		SendPeakRMS.kr(signal, replyRate: rmsReplyRate, peakLag: rmsPeakLag, cmdName:"/rms", replyID: orbitIndex)

	}, [\kr, \ir, \ir, \kr, \kr, \kr]).add;



	/*

	Effect synths

	Each must have at least: dryBus, effectBus, gate

	dryBus and effectBus have \ir as rates (they shouldn't change at runtime)

	*/



	if(\SwitchDelay.asClass.notNil) {

		SynthDef("dirt_delay" ++ numChannels, { |fxBus, effectBus, gate = 1, delaytime, delayfeedback, lock = 0, cps = 1|
			var signal;
			var input = In.ar(fxBus+(offsetDict[\delay]*numChannels), numChannels);
			var maxDelayTime = 4;

			delayfeedback = delayfeedback.max(0);
			delaytime = delaytime * if(lock, reciprocal(cps), 1);
			delaytime = delaytime.clip(0, maxDelayTime); // just to be sure
			// from sc3-plugins
			signal = \SwitchDelay.asClass.ar(input, 1, 1, delaytime, delayfeedback, maxDelayTime);

			DetectSilence.ar(signal, time:1, doneAction: 1);
			// doesn't work properly. We don't really know when it's not used anymore.
			// this would have to be an explicit signal from sclang

			signal = signal * EnvGen.kr(Env.asr, gate, doneAction:2);

			DirtPause.ar(signal, graceTime:4);

			Out.ar(effectBus, signal);

		}, [\ir, \ir]).add;
	} {
		"\n\n ---- SC3-Plugins not found. This is not a problem."
		"Note that we are using a comb delay, which may not sound the same as SwitchDelay from the plugins".postln;

		SynthDef("dirt_delay" ++ numChannels, { |fxBus, effectBus, gate = 1, delaytime, delayfeedback, lock = 0, cps = 1|
			var signal = In.ar(fxBus+(offsetDict[\delay]*numChannels), numChannels);
			var maxDelayTime = 4;
			var decayTime;

			delayfeedback = delayfeedback.clip(0, 0.99);
			delaytime = delaytime * if(lock, reciprocal(cps), 1);
			delaytime = delaytime.clip(0, maxDelayTime); // just to be sure
			decayTime = log2(-60.dbamp) / log2(delayfeedback) * delaytime;
			decayTime = decayTime.clip(0, 20);

			signal = CombL.ar(signal, maxDelayTime, delaytime.lag(1), decayTime);

			signal = LeakDC.ar(signal) * EnvGen.kr(Env.asr, gate, doneAction:2);

			DirtPause.ar(signal, graceTime:4);

			Out.ar(effectBus, signal);
		}, [\ir, \ir]).add;
	};


	// thanks to Jost Muxfeld and James McCartney
	// note that "size" is not room size, just the feed level into the room

	SynthDef("dirt_reverb" ++ numChannels, { |fxBus, effectBus, gate = 1, size = 0.1|
		var in, snd, loop, depth;

		in = In.ar(fxBus+(offsetDict[\room]*numChannels), numChannels).asArray.sum;

		4.do { in = AllpassN.ar(in, 0.03, { Rand(0.005, 0.02) }.dup(numChannels), 1) };

		depth = size.lag(0.02).linexp(0, 1, 0.01, 0.98); // change depth between 0.1 and 0.98
		loop = LocalIn.ar(numChannels) * { depth + Rand(0, 0.05) }.dup(numChannels);
		loop = OnePole.ar(loop, 0.5);  // 0-1

		loop = AllpassN.ar(loop, 0.05, { Rand(0.01, 0.05) }.dup(numChannels), 2);

		loop = DelayN.ar(loop, 0.3, [0.19, 0.26] + { Rand(-0.003, 0.003) }.dup(2));
		loop = AllpassN.ar(loop, 0.05, { Rand(0.03, 0.15) }.dup(numChannels), 2);

		loop = loop + in;
		loop = LeakDC.ar(loop);

		LocalOut.ar(loop);

		snd = loop;

		DirtPause.ar(snd, graceTime:4);

		snd = snd * EnvGen.kr(Env.asr, gate, doneAction:2);

		Out.ar(effectBus, snd);

	}, [\ir, \ir, \ir, \ir]).add;


	// "leslie" controls dry/wet
	// "lrate" is the modulation rate (typical vintage rates would be 6.7 for "fast", 0.7 for "slow")
	// "lsize" is the physical size of the cabinet in meters, this mostly affects the Doppler amount (pitch warble)

	SynthDef("dirt_leslie" ++ numChannels, { |fxBus, effectBus, gate = 1, lrate=6.7, lsize=0.3|
		var in, distance, throb, sound1, sound2, bal1, bal2, snd;

		in = In.ar(fxBus+(offsetDict[\leslie]*numChannels), numChannels);

		in = if(numChannels > 2) { in.clump(2).sum } { in.dup };
		distance = SinOsc.ar(Lag.kr(lrate,10), 0).range(0, lsize);
		throb = SinOsc.ar(Lag.kr(lrate*0.8, 20), 0).range(0,lsize*1.3);
		bal1 = SinOsc.kr(Lag.kr(lrate*0.8, 4), pi/2).range(-0.2,0.2);
		bal2 = SinOsc.kr(Lag.kr(lrate,2), pi/2).range(-0.4, 0.4);
		sound2 = HPF.ar(in, 800);
		sound1 = in - sound2;
		sound1 = (1.0 - throb) * sound1;
		sound1 = Balance2.ar(sound1[0], sound1[1], bal1);
		sound2 = DelayC.ar(sound2, 1, distance / 343);
		sound2 = (1.0 - distance) * sound2;
		sound2 = Balance2.ar(sound2[0], sound2[1], bal2);

		snd = 1.4 * (sound1 + sound2);

		DirtPause.ar(snd, graceTime:4);
		snd = snd * EnvGen.kr(Env.asr, gate, doneAction:2);

		case(
			{ numChannels == 1 }, { snd = snd.sum },
			{ numChannels > 2 }, {
				snd = [
					// wild interpretation
					PanAz.ar(numChannels, snd[0], LFSaw.kr(lrate)),
					PanAz.ar(numChannels, snd[1], LFSaw.kr(lrate) + 1)
				].sum
			}
		);


		Out.ar(effectBus, snd);

	}, [\ir, \ir]).add;

	SynthDef("dirt_tape" ++ numChannels, { |fxBus, effectBus, gate=1, taped, tapefb, tapec|
		var in = In.ar(fxBus+(offsetDict[\tape]*numChannels), numChannels);
		var maxDelayTime = 8;
		var decayTime, delay, delayfb, loop;

		delayfb = tapefb.clip(0,0.99);
		delay = (Lag.kr(taped, 0.2) + LPF.kr(PinkNoise.kr(0.015), 1)).clip(0.001, maxDelayTime); //wow
		loop = LocalIn.ar(numChannels);
		loop = DelayL.ar((loop*delayfb) + in, maxDelayTime, delay*SinOsc.kr(1/delay, 0.25, 0.001, 1));
		loop = loop * WhiteNoise.ar(0.01, 1); //flutter
		loop = MantissaMask.ar(loop, 2);
		loop = CompanderD.ar(loop, 0.3, 1, (1-tapec).clip(0,1), 0.005, 0.005); //compression
		loop = LPF.ar(tanh(loop)*1.2, (2700+SinOsc.kr(0.1, mul:20)-(1000*tapec)).clip(20,10000)); //distortion and hi cutoff
		loop = HPF.ar(loop,20);
		LocalOut.ar(LeakDC.ar(loop));
		DirtPause.ar(loop, graceTime:4);
		loop = loop * EnvGen.kr(Env.asr, gate, doneAction:2);
		Out.ar(effectBus, loop);
	}, [\ir, \ir]).add;

	SynthDef("dirt_hall" ++ numChannels, { |fxBus, effectBus, gate=1,
		hallfb=0.2, hallcutoff=3500, halltail=1, hallpredelay=0, halldelay=0, halldelayt=1, halldelayfb=0.5, hallshift = (-2)|
		var in = In.ar(fxBus+(offsetDict[\hall]*numChannels), numChannels);
		var snd;
		var a1d = 337 / 44100;
		var a2d = 113 / 44100;
		var a3d =  37 / 44100;
		var a4d = 997 / 44100;
		var a5d = 4639/ 44100;
		var del = ([1687, 1601, 2053, 2251, 6043, 14831] + LFNoise2.ar(0.1,33)) / 44100;
		var lrdel = 0.002;
		var feedback = hallfb.linlin(0,10,0.3,5.3);
		var lagcutoff = Lag.kr(hallcutoff, 0.2);
		var lagshift = Lag.kr(hallshift, 0.2);

		snd = DelayN.ar(in, 0.2, hallpredelay); //pre-delay
		snd = feedback * LocalIn.ar(2) + snd; // first number is feedback
		snd = AllpassN.ar(snd, 0.5, a1d+LFNoise2.ar(0.1, a1d/2), a1d*19.37);
		snd = AllpassN.ar(snd, 0.5, a2d+LFNoise2.ar(0.1, a3d), a2d*19.37);
		snd = AllpassN.ar(snd, 0.5, a3d+LFNoise2.ar(0.1, a3d/4), a3d*19.37);
		snd = AllpassN.ar(snd, 1.5, a4d+LFNoise2.ar(0.1, a2d), a4d*19.37);
		snd = AllpassN.ar(snd, 2.5, a5d+LFNoise2.ar(0.1, a1d), a5d*19.37);
		snd[0] = Mix.ar( CombN.ar(snd[0], 4.0, del, del*19.37*halltail*2+LFNoise2.ar(0.1, 0.2))/6);
		snd[1] = Mix.ar( CombN.ar(snd[1], 4.0, del+lrdel, del*19.37*halltail*2+LFNoise2.ar(0.11, 0.2))/6);
		snd = halldelay * SwitchDelay.ar(in, 0, 1, halldelayt*[1.0, 1.0+lrdel], halldelayfb) + snd;
		snd = LPF.ar(snd, (lagcutoff * 1.732).clip(20,20000)); // damping
		snd = LPF.ar(snd, (lagcutoff / 1.732).clip(20,20000)); // damping
		snd = HPF.ar(snd, 64);
		snd = FreqShift.ar(snd, [lagshift+LFNoise2.ar(0.1, lagshift/2), lagshift+LFNoise2.ar(0.11,lagshift/2)]); // fun
		LocalOut.ar(LeakDC.ar(snd));

		DirtPause.ar(in+snd, graceTime:8);
		snd = snd * EnvGen.ar(Env.asr, gate, doneAction:2);
		Out.ar(effectBus, snd);
	}, [\ir, \ir]).add;

	SynthDef("dirt_arena" ++ numChannels, { |fxBus, effectBus, gate=1, arenatime=1, arenafb=0, arenacutoff=8000|
		var in = In.ar(fxBus+(offsetDict[\arena]*numChannels), numChannels);
		var ta = Lag.kr(arenatime, 0.2);
		var fc = Lag.kr(arenacutoff, 0.2);
		var fb = Lag.kr(arenafb.linlin(0,2,0,0.8), 0.2);
		var snd = LPF.ar(in, fc);

		snd = fb * LocalIn.ar(numChannels) + snd;
		snd = JPverbRaw.ar(snd[0], snd[1],
			damp:fc.explin(20,20000,1,0),
			earlydiff:0.8, lowband:500, highband:2000, lowx:0.707, midx:1, highx:1.5, size:5,
			t60:ta*5);
		snd = tanh(snd);
		snd = BHiShelf.ar(snd, fc, db:-20);
		LocalOut.ar(LeakDC.ar(snd));
		DirtPause.ar(in+snd, graceTime:8);
		snd = snd * EnvGen.ar(Env.asr, gate, doneAction:2);
		Out.ar(effectBus, snd);
	}, [\ir, \ir]).add;




	"---- core synth defs loaded ----".postln;

}.value
);
