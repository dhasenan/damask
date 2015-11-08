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

	// Set up logging.
	auto log = new MultiLogger();
	log.insertLogger("stdout", new FileLogger(std.stdio.stdout, LogLevel.trace));
	log.insertLogger("file", new FileLogger("dmud.log", LogLevel.info));
	dmud.log.logger = log;

	// Load the world.
	World.current = loadAll("");

	// Start listening.
	ushort port = 5005;
	scheduler = new FiberScheduler();
	auto server = new Server(port);
	logger.infof("listening on port %d", port);

	// Start the scheduler (by giving it an empty task).
	scheduler.start(() {});
	return 0;
}
