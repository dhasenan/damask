module dmud.util;

import core.thread;
public import core.thread : Fiber;
import std.concurrency;

@safe:

@trusted void spawn(void delegate() @safe dg) {
	assert(!!scheduler);
	scheduler.spawn(dg);
}

@trusted void yield() {
	scheduler.yield();
}

@trusted Fiber getRunning() {
	return Fiber.getThis();
}
