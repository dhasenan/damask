module dmud.time;

// TODO in-mud calendar; day / night cycle; seasons
// TODO concrete conversion to real-world time?
struct Time {
	static Time zero = {0};
	long ticks;
	
	bool opEquals(Time other) {
		return ticks == other.ticks;
	}
	
	int opCmp(Time other) {
		return ticks == other.ticks ? 0 :
		ticks < other.ticks ? -1 : 1;
	}
	
	Time opBinary(string s)(Span other) if (s == "+") {
		return Time(ticks + other.ticks);
	}
	
	Time opBinary(string s)(Span other) if (s == "-") {
		return Time(ticks - other.ticks);
	}
	
	Time opBinary(string s)(Time other) if (s == "-") {
		return Span(ticks - other.ticks);
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