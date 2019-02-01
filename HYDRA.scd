(
/*
 * Hydra
 *
 * TODO:
 * Gain control issues
 * Full GUI implimentation
 * Map pressure data to params
 * Video integration
 */

//--------------------------------------------------------------
// init

~numInputChannels  = 4;
~numOutputChannels = 8;
~spatialize = true;
~runQuneo = true;
~runRoutines = false;

// granulation
~dur    = 8;
~rate   = 1;
~pscale = 2;
~buflen = 16;

// gain
~sourceGain = -22.dbamp;
~mixerGain  = 32.dbamp;

// spatialization - VBAP
~arrayGen = { |n|
	all {:
		if(360/n*x <= 180,
			{ 360/n*x },
			{ (360/n*x)-360 }),
		x <- (0..(n-1))
	};
};
~speakerArray = ~arrayGen.(~numOutputChannels);
~v0 = VBAPSpeakerArray.new(2, ~speakerArray);

// paths
~cwd = thisProcess.nowExecutingPath.dirname;
~audioDir = "samples";

// ~quneo
if(~runQuneo, {
    (~cwd +/+ "quneo/quneo.scd").loadPath;
    ~loopPads = (12..15) ++ (8..11);
    ~livePads = (4..7);
    ~procPads = (0..3);
});

// busses
~procBus = 20;
~nodeBus = 60;
~mixBus  = 100;

// processing
~looperType = \looperSpread;
~effect0 = \granulator;
~effect1 = \stockyfx;

// nodes
~numNodes = 20;
~numSpat  = 8;

// server
o = s.options;
o.memSize_(2e6);
o.numInputBusChannels  = ~numInputChannels;
o.numOutputBusChannels = ~numOutputChannels;
o.numAudioBusChannels  = 140;

s.waitForBoot({

	//--------------------------------------------------------------
	// buffers

	// audio files
	~audio = (~cwd +/+ ~audioDir +/+ "*").pathMatch[0..7].collect { |file| Buffer.read(s, file) };

	// jGrain buffers
	~b0 = Buffer.alloc(s, 44100 * ~buflen, numChannels:1);
	~b1 = Buffer.alloc(s, 44100 * ~buflen, numChannels:1);
	~b2 = Buffer.alloc(s, 44100 * ~buflen, numChannels:1);
	~b3 = Buffer.alloc(s, 44100 * ~buflen, numChannels:1);

    ~grainBufs = [~b0, ~b1, ~b2, ~b3];

	// secondary grain buffers
	~gBufs = Array.fill(4, { Buffer.alloc(s, s.sampleRate * 16) });

	// spat buffer
	~vb0 = ~v0.loadToBuffer;

	s.sync;

	//--------------------------------------------------------------
	// grains

	~grains0 = JGrain(s)
	.buf_(~b0)
	.rate_(~rate)
	.pos_(0)
	.dur_(~dur)
	.pan_(0)
	.delta_( { 1.001.rrand(1.01) } )
	.amp_(0.0)
	.start(~nodeBus+32+0);

	~grains1 = JGrain(s)
	.buf_(~b1)
	.rate_(~rate)
	.pos_(0)
	.dur_(~dur)
	.pan_(0)
	.delta_( { 1.001.rrand(1.01) } )
	.amp_(0.0)
	.start(~nodeBus+32+2);

	~grains2 = JGrain(s)
	.buf_(~b2)
	.rate_(~rate)
	.pos_(0)
	.dur_(~dur)
	.pan_(0)
	.delta_( { 1.001.rrand(1.01) } )
	.amp_(0.0)
	.start(~nodeBus+32+4);

	~grains3 = JGrain(s)
	.buf_(~b3)
	.rate_(~rate)
	.pos_(0)
	.dur_(~dur)
	.pan_(0)
	.delta_( { 1.001.rrand(1.01) } )
	.amp_(0.0)
	.start(~nodeBus+32+6);

	~grains = [~grains0, ~grains1, ~grains2, ~grains3];

	s.sync;

	//--------------------------------------------------------------
	// sources

	SynthDef(\live, { |amp=0.0, rate=1.0, pan=0, send=1.0, inbus=0, outbus, sendbus|
		var in, mix;
		in = SoundIn.ar(inbus).dup;
		mix = LPF.ar(in, 3000);
		Out.ar(sendbus, mix * send * ~sourceGain);
		Out.ar(outbus, mix * Lag.kr(amp, 2) * ~sourceGain);
	}).add;


	SynthDef(\looper, { |bufnum, amp=0.0, rate=1.0, spread=0, send=1.0, outbus, sendbus|
		var in = PlayBuf.ar(2, bufnum, rate, loop:1);
		Out.ar(sendbus, in *  send * ~sourceGain);
		Out.ar(outbus, in *  Lag.kr(amp, 2) * ~sourceGain);
	}).add;


	SynthDef(\looperSpread, { |bufnum, amp=0.0, rate=1.0, spread=0.5, send=1.0, outbus, sendbus|
		var in = Array.fill(3, { |i|
			PlayBuf.ar(1, bufnum, rate, startPos:BufFrames.kr(bufnum) * (i+1).reciprocal, loop:1);
		});
		in = Pan2.ar(in[0], -1 * spread) + Pan2.ar(in[1], 0) + Pan2.ar(in[2], spread);
		Out.ar(sendbus, in *  send * ~sourceGain);
		Out.ar(outbus, in *  Lag.kr(amp, 2) * ~sourceGain);
	}).add;


	SynthDef(\looper2ch, { |bufnum, amp=0.0, rate=1.0, spread=0, send=1.0, outbus, sendbus|
		var in = Array.fill(2, { |i|
			PlayBuf.ar(2, bufnum, rate, startPos:BufFrames.kr(bufnum) * (i+1).reciprocal, loop:1);
		}).sum;
		Out.ar(sendbus, in *  send * ~sourceGain);
		Out.ar(outbus, in *  Lag.kr(amp, 2) * ~sourceGain);
	}).add;


	SynthDef(\looper4ch, { |bufnum, amp=0.0, rate=1.0, pan=0, send=1.0, outbus, sendbus|
		var in = Array.fill(3, { |i|
			PlayBuf.ar(2, bufnum, rate, startPos:BufFrames.kr(bufnum) * (i+1).reciprocal, loop:1);
		}).sum;
		Out.ar(sendbus, in *  send * ~sourceGain);
		Out.ar(outbus, (in++in) *  Lag.kr(amp, 2) * ~sourceGain);
	}).add;

	//--------------------------------------------------------------
	// processing

	SynthDef(\melt, { |inbus, outbus, amp=0, mod_scale=1.0|
		var in, d1, d2, mod, pan, mix;

		in = In.ar(inbus, 2);
		mod = Lag.kr(mod_scale);

		d1 = Array.fill(6, {
			BPF.ar(
				CombC.ar(
					in[0],
					15.0,
					LinLin.kr(
						SinOsc.kr(rrand(1/50, 1/64) * mod),
						-1.0,
						1.0,
						rrand(4.0, 6.0) * mod,
						rrand(8.0, 12.0) * mod ),
					10) * mod,
				rrand(200, 10000),
				0.3)
		} ).sum / 2;

		d2 = Array.fill(6, {
			BPF.ar(
				CombC.ar(
					in[1],
					15.0,
					LinLin.kr(
						SinOsc.kr(rrand(1/50, 1/64) * mod),
						-1.0,
						1.0,
						rrand(4.0, 6.0) * mod,
						rrand(8.0, 12.0) * mod ),
					10) * mod_scale,
				rrand(200, 10000),
				0.3)
		} ).sum / 2;


		pan = LinLin.kr(SinOsc.kr(0.1/128), -1.0, 1.0, -0.5, 0.5);
		d1 = Pan2.ar(d1, pan);
		d2 = Pan2.ar(d2, -1.0*pan);
		mix = (d1 + d2) * Lag.kr(amp, 2);

		Out.ar(outbus, mix);
	}).add;


	SynthDef(\chorus, { |amp=0.0, predelay=0.08, speed=0.05, depth=0.1, ph_diff=0.5, inbus, outbus|
		var channels, in, mod1, mod2, sig1, sig2, mix, numDelays = 3;
		channels = inbus + [0,8,16];
		in = [In.ar(channels).sum, In.ar(channels+1).sum] * numDelays.reciprocal;

		mod1 = Array.fill(numDelays, { |i|
			LFPar.kr(speed * rrand(0.94, 1.06), ph_diff * i, depth, predelay);
		});
		mod2 = Array.fill(numDelays, { |i|
			LFPar.kr(speed * rrand(0.94, 1.06), ph_diff * i, depth, predelay);
		});
		sig1 = DelayC.ar(in[0], 0.5, mod1).sum;
		sig2 = DelayC.ar(in[1], 0.5, mod2).sum;

		mix = [sig1, sig2] * amp;
		Out.ar(outbus, mix);
	}).add;

	SynthDef(\stockyfx, { |inbus, outbus, shift=0.0, rate=1.0, amp=0.0|
		var input, fx;
		var shifted;
		var a,c,z,y,in;
		c = 2; // number of comb delays
		a = 3; // number of allpass delays
		input=In.ar(inbus, 2);
		//simulate slow down
		shifted= PitchShift.ar(input, 0.01,rate);
		input= (shift*shifted)+((1.0-shift)*input);
		// reverb predelay time :
		z = DelayN.ar(input, 0.048,0.048);
		//for delaytime if want modulation-	//LFNoise1.kr(0.1.rand, 0.04, 0.05)
		y = Mix.arFill(c,{CombL.ar(z,0.1,rrand(0.01, 0.1),5)});
		// chain of 4 allpass delays on each of two channels (8 total) :
		a.do({ y = AllpassN.ar(y, 0.051, [rrand(0.01, 0.05),rrand(0.01, 0.05)], 1) });
		Out.ar(outbus, ((0.33*y) + input)*amp);
	}).add;


	SynthDef(\granulator, { |inbus, outbus, amp=0.0, bufnum, pdisp = 0.01,
		                  tdisp = 0.02, speed=1.0, overlap=1.0, pcenter=0.0|
		var frames, sRate, recHead, rec, in, trig, mix, eff, rate, dur, pan, center;

		// in      = In.ar(inbuf);
		in      = In.ar(inbus, 2).sum;
		frames  = BufFrames.kr(bufnum);
		sRate   = BufSampleRate.kr(bufnum);
		recHead = Phasor.ar(1, BufRateScale.kr(bufnum), 0, frames, 0);
		rec     = BufWr.ar(in, bufnum, recHead);
		dur     = 0.6 + SinOsc.kr(0.1, mul:0.4);
		pdisp   = pdisp + 1;
		trig    = Impulse.ar(overlap / dur);
		rate    = speed * TExpRand.kr(pdisp.reciprocal, pdisp, trig);
		center  = Wrap.ar(recHead - (dur * rate * 0.5), 0, frames-1) - TRand.kr(0, tdisp, trig);
		// pan     = pcenter + WhiteNoise.kr(0.1);
		// pan     = WhiteNoise.kr(0.5);
		pan = pcenter;

		mix     = TGrains.ar(2, trig, bufnum, rate, center/sRate, dur, pan, 1.0, 2);
		eff     = mix;
		6.do({ eff = LPF.ar( AllpassC.ar( eff, 0.5, 0.1.rand, 1), 8000 ); });
		mix = (mix + eff) * amp;

		Out.ar(outbus, mix);
	}).add;


	SynthDef(\proc0, { |amp=0, inbus, outbus|
		var channels, in;
		channels = inbus + [0,8,16];
		in = [In.ar(channels).sum, In.ar(channels+1).sum];
		Out.ar(outbus, in * amp);
	}).add;


	SynthDef(\proc1, { |amp=0, inbus, outbus|
		var channels, in;
		channels = inbus + [0,8,16];
		in = [In.ar(channels).sum, In.ar(channels+1).sum];
	}).add;

	//--------------------------------------------------------------
	// sampling

	SynthDef(\grainRec, { |bufnum, inbus, len=5, recLevel=1|
		var in, mix, env;
		in = In.ar(inbus, 2).sum;
		env = EnvGen.ar(Env.linen(~buflen*0.15, ~buflen*0.7, ~buflen*0.15), doneAction:2);
		mix = LPF.ar(in, 8000) * recLevel * env;
		RecordBuf.ar(mix, bufnum);
	}).add;


	SynthDef(\grainRecLive, { |bufnum, inbus, len=5, recLevel=1|
		var in, mix, env;
		in = SoundIn.ar([inbus,inbus+1]).sum;
		env = EnvGen.ar(Env.linen(~buflen*0.15, ~buflen*0.7, ~buflen*0.15), doneAction:2);
		mix = LPF.ar(in, 8000) * recLevel * env;
		RecordBuf.ar(mix, bufnum);
	}).add;


	SynthDef(\grainRecMulti, { |bufnum, inbus0, inbus1, len=5, recLevel=1|
		var in, mix, env;
		in = In.ar(inbus0, 2).sum + In.ar(inbus1, 2).sum;
		env = EnvGen.ar(Env.linen(~buflen*0.15, ~buflen*0.7, ~buflen*0.15), doneAction:2);
		mix = LPF.ar(in, 8000) * recLevel * env;
		RecordBuf.ar(mix, bufnum);
	}).add;

	//--------------------------------------------------------------
	// mixers

	SynthDef(\node, { |amp=1, inbus, outbus|
		var in = In.ar(inbus, 2);
		Out.ar(outbus * amp, in);
	}).add;


	SynthDef(\mixer, { |amp=1, inbus|
		var channels, in, mix;
		channels = inbus + (0,2..38);
		in = [In.ar(channels).sum, In.ar(channels+1).sum];
		mix = in * Lag.kr(amp, 2) * ~mixerGain;
		Out.ar(0, mix);
	}).add;


	SynthDef(\vbap, { |inbus, amp=1, azi=0, spread=0|
		var in, aziL, spreadL, osc, spat;
		in = In.ar(inbus, 2).sum;
		aziL = Lag.kr(azi, 2);
		spreadL = Lag.kr(spread, 2);
		// osc = SinOsc.kr(16.reciprocal, phase:rand(2*pi)) + 1 * 0.5;
		// spat = VBAP.ar(~numSpat, in, ~vb0.bufnum, aziL * osc, 0, spreadL);
		spat = VBAP.ar(~numSpat, in, ~vb0.bufnum, aziL, 0, spreadL);
		Out.ar(0, spat*amp);
	}).add;


	SynthDef(\vbapMulti, { |inbus, amp=1, azi=0, spread=0|
		var channels, in, aziL, spreadL, osc, spat;
		channels = inbus + [0, 8, 16, 24];
        in = [In.ar(channels).sum, In.ar(channels+1).sum].sum;
		aziL = Lag.kr(azi, 2);
		spreadL = Lag.kr(spread, 2);
		// osc = SinOsc.kr(16.reciprocal, phase:rand(2*pi)) + 1 * 0.5;
		// spat = VBAP.ar(~numSpat, in, ~vb0.bufnum, aziL * osc, 0, spreadL);
		spat = VBAP.ar(~numSpat, in, ~vb0.bufnum, aziL, 0, spreadL);
		Out.ar(0, spat*amp);
	}).add;

	s.sync;

	//--------------------------------------------------------------
	// utility

    ~sampleNode = { |node, grainIndex|
		Synth(\grainRec, [\bufnum, ~grainBufs[grainIndex].bufnum, \inbus, ~nodeBus + (node*2)], ~recGroup);
		("rec: " + grainIndex.asString).postln;
    };

    ~sampleLive = { |liveIndex, grainIndex|
		Synth(\grainRecLive, [\bufnum, ~grainBufs[grainIndex].bufnum, \inbus, liveIndex], ~recGroup);
		("rec: " + grainIndex.asString).postln;
    };

	~lerp = { |a0, a1, x|
		var s0, v0;
		s0 = ControlSpec(a0, a1, \lin, 0.00001);
		v0 = s0.map(x);
		v0;
	};

	~lerpV = { |v0, v1, x|
		var lerped = Array.newClear(v0.size);
		for(0, v0.size-1, { |i|
			lerped[i] = ~lerp.(v0[i], v1[i], x);
		});
		lerped;
	};

/*	~autoSpat = {
		for(0, ~numSpat-1, { |i|
			var phase, iphase;
			phase = ((2*pi) / ~numSpat) * i;
			iphase = sin(2*pi*freq*
			~spat[i].set(\azi,
		});
	};*/

	//--------------------------------------------------------------
	// routing

	//groups
	~srcGroup  = ParGroup.new;
	~procGroup = ParGroup.after(~srcGroup);
	~nodeGroup = ParGroup.after(~procGroup);
	~recGroup  = ParGroup.after(~nodeGroup);
	~mixGroup  = ParGroup.after(~recGroup);

	// mixer
	if(~spatialize, {
		~spat = Array.newClear(~numSpat);
		for(0, ~numSpat-1, { |i|
            if(i < 4,
                { ~spat[i] = Synth(\vbap, [\inbus, ~mixBus+32+(i*2)], ~mixGroup) },
				{ ~spat[i] = Synth(\vbapMulti, [\inbus, ~mixBus +((i%4)*2)], ~mixGroup) }
            );
		});
	}, {
		~mix = Synth(\mixer, [\inbus, ~mixBus], ~mixGroup);
	});

	// nodes
	~nodes = Array.newClear(~numNodes);
	for(0, ~numNodes-1, { |i|
		~nodes[i] = Synth(\node, [
			\inbus,  ~nodeBus+(i*2),
			\outbus, ~mixBus+(i*2)
		], ~nodeGroup);
	});

	// samplers
	~loopers = Array.newClear(~audio.size);
	~melters = Array.newClear(~audio.size);
	for(0, ~audio.size-1, { |i|
		~loopers[i] = Synth(\looperSpread, [
			\bufnum, ~audio[i].bufnum,
			\sendbus, ~procBus + (i*2),
			\outbus,  ~nodeBus + (i*2)
		], ~srcGroup);

		~melters[i] = Synth(\melt, [
			\inbus,  ~procBus + (i*2),
			\outbus, ~nodeBus + (i*2)
		], ~procGroup);
	});

	// live ins
	~liveIns = Array.newClear(~numInputChannels);
	~liveMelters = Array.newClear(~numInputChannels);
	for(0, ~numInputChannels-1, { |i|
		~liveIns[i] = Synth(\live, [
			\inbus,   i,
			\sendbus, ~procBus+16+(i*2),
			\outbus,  ~nodeBus+16+(i*2)
		], ~srcGroup);

		~liveMelters[i] = Synth(\melt, [
			\inbus,  ~procBus+16+(i*2),
			\outbus, ~nodeBus+16+(i*2)
		], ~procGroup);
	});

	// processing
	~proc0 = Array.newClear(4);
	~proc1 = Array.newClear(4);
	for(0, 3, { |i|
		~proc0[i] = Synth(~effect0, [
			\inbus,  ~procBus + (i*2),
			\outbus, ~nodeBus + 24 + (i*2)
		], ~procGroup);

		~proc1[i] = Synth(~effect1, [
			\inbus,  ~procBus + (i*2),
			\outbus, ~nodeBus + 24 + (i*2)
		], ~procGroup);
	});

	//--------------------------------------------------------------
	// effect parameters

	~macroControl = 0.0;

	// grain parameters
	// pdisp, tdisp, speed, overlap
	~gp0 = [0.01, 0.02, 0.5, 7];
	~gp1 = [0.1,  0.01, 0.9, 3];

	~gp0 = [0.01, 0.01, 0.5, 7];
	~gp1 = [0.1,  0.001, 2, 3];
	~gp = ~gp0;

	if(~effect0 == \granulator, {
		for(0, 3, { |i|
			~proc0[i].set(\bufnum, ~gBufs[i].bufnum);
			~proc0[i].set(\pdisp, ~gp[0], \tdisp, ~gp[1], \speed, ~gp[2], \overlap, ~gp[3]);
		});
	});

	if(~effect1 == \granulator, {
		for(0, 3, { |i|
			~proc1[i].set(\bufnum, ~gBufs[i].bufnum);
			~proc1[i].set(\pdisp, ~gp[0], \tdisp, ~gp[1], \speed, ~gp[2], \overlap, ~gp[3]);
		});
	});

	s.sync;

	//--------------------------------------------------------------
	// gui

	~width = ServerMeterView.getWidth(~numInputChannels, ~numOutputChannels);
	~height = 420;

	~win = Window("HYDRA", Rect(Window.screenBounds.width - ~width, Window.screenBounds.height, ~width, ~height));
	~win.front;
	~win.view.decorator = FlowLayout(~win.view.bounds);
	~win.view.decorator.gap=2@2;
	~win.onClose_({ fork{ ~run = false; 1.wait; Server.killAll } });
	~win.alwaysOnTop_(true);

	// meter
	~win.view.decorator.nextLine;
	ServerMeterView.new(s, ~win, Point(0, 0), ~numInputChannels, ~numOutputChannels);

	// control specs
	~rs0 = ControlSpec(1.0, 0.01, \lin, 0.0, 1.0);
	~rs1 = ControlSpec(1.0, ~pscale,  \lin, 0.0, 1.0);
	~ds0 = ControlSpec(~dur, 0.0004, \exp, 0.0, 1.0);
	~ds1 = ControlSpec(~dur, 0.004,  \exp, 0.0, 1.0);

	// grain sliders
	~win.view.decorator.nextLine;
	~panCtl = EZSlider(~win, ~width @ 40, "Pan ", ControlSpec(0.0, 1.0, \lin, 0.00001), unitWidth:30)
	.action_({ |ez|
		var val = ez.value;
		// for(0, ~grains.size-1, { |i| ~grains[i].pan_({ val.rand2 }) });

		~grains0.pan_( {(ez.value).rand2} );
		~grains1.pan_( {(ez.value).rand2} );
		~grains2.pan_( {(ez.value).rand2} );
		~grains3.pan_( {(ez.value).rand2} );
	})
	.value_(0);

	~win.view.decorator.nextLine;
	~durCtl = EZSlider(~win, ~width @ 40, "Dur ", ControlSpec(0.001, 1, \lin, 0.00001), unitWidth:30)
	.action_({ |ez|
		var val = ez.value;
		// for(0, ~grains.size-1, { |i| ~grains[i].dur_({ val * ~dur }) });

		~grains0.dur_( ez.value * ~dur );
		~grains1.dur_( ez.value * ~dur );
		~grains2.dur_( ez.value * ~dur );
		~grains3.dur_( ez.value * ~dur );
	})
	.value_(~dur);

	~win.view.decorator.nextLine;
	~rateCtl = EZSlider(~win, ~width @ 40, "Rate ", ControlSpec(0.0, 1.0, \lin, 0.00001), unitWidth:30)
	.action_({ |ez|
		var ri, r0;
		r0 = ~rs0.map(ez.value) * ~rate;
		ri = ~rs1.map(ez.value) * ~rate;
		// for(0, ~grains.size-1, { |i| ~grains[i].rate_({ r0.rrand(ri) }) });

		~grains0.rate_({ r0.rrand(ri) });
		~grains1.rate_({ r0.rrand(ri) });
		~grains2.rate_({ r0.rrand(ri) });
		~grains3.rate_({ r0.rrand(ri) });
	})
	.value_(0);

	~win.view.decorator.nextLine;
	~deltaCtl = EZSlider(~win, ~width @ 40, "Delta ", ControlSpec(0.0, 1.0, \lin, 0.00001), unitWidth:30)
	.action_({ |ez|
		var di, d0;
		d0 = ~ds0.map(ez.value * 0.5);
		di = ~ds1.map(ez.value * 0.5);
		// for(0, ~grains.size-1, { |i| ~grains[i].delta_({ d0.rrand(di) }) });

		~grains0.delta_({ d0.rrand(di) });
		~grains1.delta_({ d0.rrand(di) });
		~grains2.delta_({ d0.rrand(di) });
		~grains3.delta_({ d0.rrand(di) });
	})
	.value_(0);

	~win.view.decorator.nextLine;

	//--------------------------------------------------------------
	// quneo

	~run = true;

	// ~quneoRoutine = Routine{
	fork {
		block { |break|
			loop {
				if( ~run.not, { break.() });

				// master
				~mixGroup.set(\amp, ~quNeo.vSliders[3].loc.value);

				// grains
				{
					~panCtl.valueAction_(~quNeo.hSliders[0].loc.value);
					~durCtl.valueAction_(~quNeo.hSliders[1].loc.value);
					~rateCtl.valueAction_(~quNeo.hSliders[2].loc.value);
					~deltaCtl.valueAction_(~quNeo.hSliders[3].loc.value);
				}.defer;

				~grains0.amp_(~quNeo.vSliders[0].loc.value * 16.dbamp);
				~grains1.amp_(~quNeo.vSliders[1].loc.value * 16.dbamp);
				~grains2.amp_(~quNeo.vSliders[2].loc.value * 16.dbamp);
				~grains3.amp_(~quNeo.lSliders[0].loc.value * 16.dbamp);

/*				~nodes[16].set(\amp, ~quNeo.vSliders[4].loc.value);
				~nodes[17].set(\amp, ~quNeo.vSliders[5].loc.value);
				~nodes[18].set(\amp, ~quNeo.vSliders[6].loc.value);
				~nodes[19].set(\amp, ~quNeo.vSliders[7].loc.value);*/

				// spat
				if(~spatialize, {
					for(0, ~numSpat-1, { |i|
						~spat[i].set(\azi, ~quNeo.vSliders[4+i].loc.value * 360);
						~spat[i].set(\spread, ~quNeo.circles[0].loc.value  * 100);
					});
				});

				// samples
				for(0, ~audio.size-1, { |i|
					~loopers[i].set(\amp, ~quNeo.pads[~loopPads[i]].y.value * (-6).dbamp);
					~melters[i].set(\amp, ~quNeo.pads[~loopPads[i]].x.value * 6.dbamp);
				});

				// live
				for(0, ~liveIns.size-1, { |i|
					~liveIns[i].set(\amp, ~quNeo.pads[~livePads[i]].y.value * (-6).dbamp);
					~liveMelters[i].set(\amp, ~quNeo.pads[~livePads[i]].x.value * 6.dbamp);
				});

				// processing
				for(0, 3, { |i|
					~proc0[i].set(\amp, ~quNeo.pads[~procPads[i]].y.value * (-6).dbamp);
					~proc1[i].set(\amp, ~quNeo.pads[~procPads[i]].x.value * 6.dbamp);
				});

				~macroControl = ~quNeo.lSliders[0].loc.value;

				if(~effect0 == \granulator, {
					for(0, 3, { |i|
						var ps = ~lerpV.(~gp0, ~gp1, ~macroControl);
						~proc0[i].set(\pdisp, ps[0], \tdisp, ps[1], \speed, ps[2], \overlap, ps[3]);
					});
				});

				if(~effect1 == \granulator, {
					for(0, 3, { |i|
						var ps = ~lerpV.(~gp0, ~gp1, ~macroControl);
						~proc1[i].set(\pdisp, ps[0], \tdisp, ps[1], \speed, ps[2], \overlap, ps[3]);
					});
				});

				0.05.wait;
			};
		};
	};


    if(~runQuneo, {
        ~quNeo.buttons[0].note.onFunc = {
            Synth(\grainRec, [\bufnum, ~b0.bufnum, \inbus, ~nodeBus+0], ~recGroup);
            Synth(\grainRecLive, [\bufnum, ~b0.bufnum, \inbus, 0], ~recGroup);
            "rec: 1".postln;
        };

        ~quNeo.buttons[1].note.onFunc = {
            Synth(\grainRec, [\bufnum, ~b1.bufnum, \inbus, ~nodeBus+2], ~recGroup);
            Synth(\grainRecLive, [\bufnum, ~b1.bufnum, \inbus, 1], ~recGroup);
            "rec: 2".postln;
        };

        ~quNeo.buttons[2].note.onFunc = {
            Synth(\grainRec, [\bufnum, ~b2.bufnum, \inbus, ~nodeBus+4], ~recGroup);
            Synth(\grainRecLive, [\bufnum, ~b2.bufnum, \inbus, 2], ~recGroup);
            "rec: 3".postln;
        };

		// ~quneoRoutine.play;
    });

	//--------------------------------------------------------------
	// routines

});
)
