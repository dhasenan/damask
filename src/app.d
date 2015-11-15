module dmud.app;

import dmud.log;
import dmud.telnet_socket;
import dmud.domain;
import dmud.loader;
import dmud.player;
import dmud.server;

import core.thread;
import std.concurrency;
import std.experimental.logger;
import std.stdio;
import std.socket;
import etc.linux.memoryerror;

int main(string[] args)
{
	// Set up segfault stacktraces.
	static if (is(typeof(registerMemoryErrorHandler))) {
		registerMemoryErrorHandler();
	}

	// Load the world.
	loadAll("");

	// Start listening.
	ushort port = 5005;
	scheduler = new FiberScheduler();
	auto server = new Server(port);
	logger.info("listening on port {}", port);

	// Start the scheduler (by giving it an empty task).
	scheduler.start(() {});
	return 0;
}
