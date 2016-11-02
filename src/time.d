module dmud.time;

import core.time;

@safe:

/**
  * SimTime is the simulation time.
  *
  * SimTime comes in discrete intervals called *ticks*. A tick is the shortest amount of time
  * an action can take. It's the shortest amount of time between two actions.
  *
  * Looking at an item should take one tick.
  *
  * Non-simulation commands might take less than one tick. For instance, if you check your skills
  * and your experience points in succession, that might execute immediately instead of in
  * separate ticks.
  *
  * A tick should generally be between 0.2 and 0.4 seconds.
  */
struct SimTime {
	enum SimTime Zero = {0};
	// This is not a constant because we may want to override it in some circumstances without
	// recompiling.
	static ubyte TicksPerSecond = 4;

	ulong ticks;
	
	bool opEquals(SimTime other) inout {
		return ticks == other.ticks;
	}
	
	int opCmp(SimTime other) inout {
		return ticks == other.ticks ? 0 :
			ticks < other.ticks ? -1 : 1;
	}
	
	SimTime opBinary(string s)(Span other) if (s == "+") {
		return SimTime(ticks + other.ticks);
	}
	
	SimTime opBinary(string s)(Span other) if (s == "-") {
		return SimTime(ticks - other.ticks);
	}
	
	SimTime opBinary(string s)(SimTime other) if (s == "-") {
		return Span(ticks - other.ticks);
	}
}

class SimClock {
	SimTime now;
	Duration tickDuration = dur!"msecs"(250);

	void tick() {
		now = now + Span.iota;
	}
}

struct Span {
	static Span zero = {0};
	static Span iota = {1};

	long ticks;

	Span opBinary(string s)(Span other) if (s == "+") {
		return Span(ticks + other.ticks);
	}
	
	Span opBinary(string s)(Span other) if (s == "-") {
		return Span(ticks - other.ticks);
	}
}
