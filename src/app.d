module dmud.app;

import dmud.telnet_socket;
import dmud.domain;
import dmud.loader;
import dmud.player;
import dmud.server;

import url;

import core.thread;
import std.concurrency;
import std.experimental.logger;
import std.stdio;
import std.socket;
import etc.linux.memoryerror;

@trusted void memoryErrorStart() {
	// Set up segfault stacktraces.
	static if (is(typeof(registerMemoryErrorHandler))) {
		registerMemoryErrorHandler();
	}
}

@trusted void setupScheduler() {
	scheduler = new FiberScheduler();
}

@trusted void startScheduler() {
	// Start the scheduler (by giving it an empty task).
	scheduler.start(() {});
}

@trusted void setupLogging() {
	auto log = new MultiLogger();
	log.insertLogger("stdout", new FileLogger(stdout));
	log.insertLogger("file", new FileLogger("dmud.log"));
	sharedLog = cast(typeof(sharedLog)) log;
}

//@safe:
int main(string[] args)
{
	memoryErrorStart;
	setupLogging;
	setupScheduler;
	loadAll("localhost".parseURL, "dmud");
	ushort port = 5005;
	auto server = new Server(port);
	info("listening on port ", port);
	startScheduler;

	return 0;
}
