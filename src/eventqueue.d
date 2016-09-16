module dmud.eventqueue;

import dmud.time;

import std.algorithm;
import std.array;

import dmud.sortedmap;
import tango.math.random.Random;

// This would be @safe, but tango isn't labeled @safe anywhere.
@trusted:

/**
  * An EventQueue is a way to arrange callbacks in time in an efficient manner.
  *
  * It can be used as part of a scheduler.
  */
class EventQueue(Elem) {
	// We implement the queue simply as a sorted queue. It's simple and convenient.
	// We could optimize further, but it won't affect the interface, so we can leave that for later.
	private SortedMap!(SimTime, Elem, "a < b", true) queue;
	private SimClock clock;
	private Random random;

	this(SimClock clock, Random random) {
		queue = new typeof(queue);
		this.clock = clock;
		this.random = random;
	}

	void schedule(Elem elem, SimTime time)
	in {
		import std.format;
		assert(time > clock.now,
				("Tried to schedule a task in the past! Time machines not implemented. " ~
				"Current time: %s; schedule time: %s").format(clock.now, time));
	} body {
		queue.insert(time, elem);
	}

	/** Schedule this for the next time slot. */
	void scheduleNext(Elem elem) {
		schedule(elem, clock.now + Span.iota);
	}

	void scheduleAround(Elem elem, SimTime time) {
		auto drift = cast(ulong)random.gammaD!(real).getRandom * 20;
		auto realTime = max(time + Span(drift), clock.now);
		schedule(elem, realTime);
	}

	Elem[] popNow() {
		auto arr = queue.getLessThan(clock.now + Span.iota).array;
		foreach (a; arr) queue.removeOne(a.key);
		return arr.map!(x => x.value).array;
	}
}

unittest {
	import std.format;
	auto clock = new SimClock;
	clock.now = SimTime(7711);
	auto rand = new Random;
	rand.seed(() => 1432617);
	auto queue = new EventQueue!int(clock, rand);
	queue.schedule(8, SimTime(7712));
	queue.schedule(1, SimTime(7714));
	queue.schedule(3, SimTime(7712));
	queue.schedule(1, SimTime(7712));
	clock.tick;
	auto n = queue.popNow;
	assert(n == [8, 3, 1], "expected: [8,1,3] actual: %s".format(n));
	clock.tick;
	assert(queue.popNow is null);
	clock.tick;
	assert(queue.popNow == [1]);
}
